#!/bin/bash

# Check parameters
env_check() {
    for variable in $@; do
        if [ -z "${!variable}" ]; then
            echo "[ERROR] Value for parameter ${variable} not found"
            exit 1
        fi
    done
    echo "[INFO] All parameters have been specified"
}

###
# Entrypoint
###
while [ -n "$1" ]; do
    case "$1" in
    --hosts | -h)
        hosts=$2
        shift
        ;;
    --user | -u)
        username=$2
        shift
        ;;
    --oldpass | -op)
        oldPassword=$2
        shift
        ;;
    --newpass | -np)
        newPassword=$2
        shift
        ;;
    --confirmpass | -cp)
        confirmPassword=$2
        shift
        ;;
    --sshuser)
        sshUser=$2
        shift
        ;;
    --sshkey)
        sshKey=$2
        shift
        ;;
    *)
        echo "[ERROR] $1 is not an option"
        ;;
    esac
    shift
done

if [ -z "${hosts}" ]; then
    env_check username oldPassword newPassword confirmPassword
    ./processing-change-password.sh ${username} ${oldPassword} ${newPassword} ${confirmPassword}
else
    env_check username oldPassword newPassword confirmPassword sshUser sshKey
    IFS=',' read -r -a array_hosts <<<"$hosts"
    for host in "${array_hosts[@]}"; do
        run="ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i ${sshKey} \
            ${sshUser}@${host} 'sudo bash -s' < processing-change-password.sh ${username} ${oldPassword} ${newPassword} ${confirmPassword} ${host}"
        eval ${run}
    done
fi
