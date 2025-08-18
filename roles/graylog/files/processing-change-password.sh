#!/bin/bash

# Check password
#
# @param newPassword        new value for password
# @param confirmPassword    same value for confirm changes
checkPassword() {
    pattern=" "
    password_min_length=6
    if [[ $1 =~ $pattern ]]; then
        echo "[ERROR] New password can't contain spaces"
        exit 1
    elif [ "${#1}" -lt "${password_min_length}" ]; then
        echo "[ERROR] New password is too short! Password must be at least 6 characters long"
        exit 1
    elif [ "$1" != "$2" ]; then
        echo "[ERROR] Values for parameters 'GRAYLOG_NEW_PASSWORD' and 'CONFIRM_GRAYLOG_NEW_PASSWORD' do not match"
        exit 1
    fi
}

###
# Waiting for the Graylog server to startup
# Error if Graylog could not startup
###
waitForGraylog() {
    echo "[INFO] Wait for Graylog server to startup"
    for ((i = 99; i >= 0; i--)); do
        responseCode="$(curl --insecure \
            --silent \
            --location \
            --output /dev/null \
            --write-out '%{http_code}\\n' \
            --request GET \
            --write-out %{http_code} "https://localhost/")"
        if [ "$responseCode" -eq "200" ]; then
            echo "[INFO] Graylog had been started"
            return
        elif [ ${i} -eq 0 ]; then
            echo "[ERROR] Status code was ${responseCode} and not [200]"
            exit 1
        fi
        echo "FAILED - RETRYING: (${i} retries left)"
        sleep 1
    done
}

###
# Method to restart the Graylog
###
restartGraylog() {
    echo "[INFO] Restarting Graylog server..."
    sudo docker restart graylog_graylog_1
    waitForGraylog
}

###
# Change admin's password of the Graylog of the Telegraf
#
# @param  newPassword  the new password, to the value of which we need to change the password
###
changeTelegrafGraylogPassword() {
    passwordLineNumber=$(sudo grep -n -B2 'name_prefix = \"t_graylog_\"' /etc/telegraf/telegraf.conf | sed -n '/password = /p' | sed 's/-.*//')
    sudo sed -i ${passwordLineNumber}'s/.*/  password = \"'${1}'\"/' /etc/telegraf/telegraf.conf
    echo "[INFO] Restarting Telegraf service..."
    sudo systemctl restart telegraf
}

###
# Change the admin password for a Graylog
#
# @param  configFilePath  the absolute path to the configuration file
# @param  oldPassword     the old password
# @param  newPassword     the new password, to the value of which we need to change the password
###
changeAdminPassword() {
    rootPasswordHash=$(sudo sed -n '/root_password_sha2/p' $1 | sed 's/root_password_sha2 = //')
    oldPasswordHash=$(echo -n $2 | sha256sum | awk '{print $1}')
    if [[ $rootPasswordHash != $oldPasswordHash ]]; then
        echo "[ERROR] The old password is incorrect."
        exit 1
    fi
    newPasswordHash=$(echo -n $3 | sha256sum | awk '{print $1}')
    sudo sed -i 's/.*root_password_sha2.*/root_password_sha2 = '${newPasswordHash}'/' $1
    restartGraylog
    telegrafStatus=$(sudo systemctl is-active telegraf)
    echo "[INFO] Telegraf status = ${telegrafStatus}"
    if [[ "${telegrafStatus}" != "unknown" ]]; then
        echo "[INFO] Change admin's password of the Graylog of the Telegraf"
        changeTelegrafGraylogPassword $3
    fi
}

###
# Change the user password for a Graylog
#
# @param   username      the username for which we want to change the password
# @param   oldPassword   the old password the value of which we want to change
# @param   newPassword   the new password, to the value of which we need to change the password
# @throws  Error         if the new password is missing, or the old password is missing or incorrect.
# @throws  Error         if the request does not have valid authentication credentials for the target resource.
# @throws  Error         if the requesting user has insufficient privileges to update the password for the given user.
# @throws  Error         if the user does not exist.
# @throws  Error         if some other error. The response code is specified in the error text.
###
changeUserPassword() {
    command="curl --user ${1}:${2} \
                        --header 'X-Requested-By: Graylog API Browser' \
                        --insecure \
                        --silent \
                        --location \
                        --request GET \
                        --write-out %{http_code} "https://localhost/api/users/${1}""
    response="$(eval $command)"
    responseCode=$(echo $response | grep "[0-9]\{3\}$" -o)
    case ${responseCode} in
    200) ;;
    401)
        echo "[ERROR] Unauthorized, the request does not have valid authentication credentials for the target resource"
        exit 1
        ;;
    403)
        echo "[ERROR] The requesting user has insufficient privileges to get information about the user."
        exit 1
        ;;
    404)
        echo "[ERROR] User does not exist."
        exit 1
        ;;
    *)
        echo "[ERROR] Unsupported error, status code - ${responseCode}"
        ;;
    esac
    userId=$(echo $response | grep "\"id\":\"[0-9a-z]\+" -o | cut -c 7-)
    if [ -z "$userId" ]; then
        echo "[ERROR] Can not get ID for the user '${1}'."
        exit 1
    fi
    data="{\"old_password\": \"${2}\", \"password\": \"${3}\"}"
    command="curl --user ${1}:${2} \
            --header 'Content-Type: application/json' \
            --header 'X-Requested-By: Graylog API Browser' \
            --insecure \
            --silent \
            --location \
            --output /dev/null \
            --request PUT \
            --data '${data}' \
            --write-out %{http_code} "https://localhost/api/users/${userId}/password""
    responseCode="$(eval $command)"
    case ${responseCode} in
    204) ;;
    400)
        echo "[ERROR] The new password is missing, or the old password is missing or incorrect."
        exit 1
        ;;
    401)
        echo "[ERROR] Unauthorized, the request does not have valid authentication credentials for the target resource"
        exit 1
        ;;
    403)
        echo "[ERROR] The requesting user has insufficient privileges to update the password for the given user."
        exit 1
        ;;
    404)
        echo "[ERROR] User does not exist."
        exit 1
        ;;
    *)
        echo "[ERROR] Unsupported error, status code - ${responseCode}"
        ;;
    esac
}

###
# Entrypoint
###
if [ $? -eq 0 ]; then
    echo "[INFO] SSH connection successfully established"
else
    echo "[ERROR] Connection failure. Check that you have defined the correct host/ssh key/ssh_user for the connection."
    exit 1
fi
checkPassword ${3} ${4}
graylogConfigFilePath=$(sudo find / -path "*/graylog/config/graylog.conf")
rootUsername=$(sudo sed -n '/root_username/p' $graylogConfigFilePath | sed 's/root_username = //')
if [[ $rootUsername = ${1} ]]; then
    changeAdminPassword ${graylogConfigFilePath} ${2} ${3}
else
    changeUserPassword ${1} ${2} ${3}
fi
if [ -z "${5}" ]; then
    echo "[INFO] Password for user '${1}' was successfully changed"
else
    echo "[INFO] Password for user '${1}' on host '${5}' was successfully changed"
fi
