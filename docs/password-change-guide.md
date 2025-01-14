The document provides information about changing users\` passwords process in Graylog:

* [Root user](#root-user)
  * [Change root user password](#change-root-user-password)
* [User](#user)
  * [Change user password using bash command](#change-user-password-using-bash-command)
  * [Change user password via Graylog REST API](#change-user-password-via-graylog-rest-api)

Graylog has default root user usually named admin. Other users can be created and configured in UI. They have special
roles with pre-configured permissions.

# Root user

The root user is default and is created during deploy. Initial password is set in inventory configuration in field
`root_password`.

```yaml
all:
  hosts:
    # ...
  vars:
    # ...
    root_password: admin
    # ...
```

## Change root user password

If you want to change root password, there is a script on host machine where Graylog is deployed on the path
`/root/graylog/`. The script will change admin password and restart Graylog container to apply changes.
Run the command:

```bash
./change-password.sh --hosts <host> --user admin --oldpass <old_password> --newpass <new_password> --confirmpass <new_password> --sshuser <ssh_user> --sshkey <ssh_key_path>
```

All parameters of script are described below:

<!-- markdownlint-disable line-length -->
| Parameter     | Short parameter | Description                                                                                                         |
| ------------- | --------------- | ------------------------------------------------------------------------------------------------------------------- |
| `hosts`       | -h              | Host machine(s) where Graylog is running. Multiple hosts can be mentioned if its have common `sshuser` and `sshkey` |
| `user`        | -u              | Login of user to change password                                                                                    |
| `oldpass`     | -op             | String with old user\`s password                                                                                    |
| `newpass`     | -np             | String with new user\`s password                                                                                    |
| `confirmpass` | -cp             | String with new user\`s password                                                                                    |
| `sshuser`     |                 | Username to establish SSH connection to host machine                                                                |
| `sshkey`      |                 | Path to file with SSH key                                                                                           |
<!-- markdownlint-enable line-length -->

The example of command with parameters set:

```bash
./change-password.sh --hosts x.x.x.x --user admin --oldpass admin1 --newpass PaSSw0rd --confirmpass PaSSw0rd --sshuser centos --sshkey ./key
```

Note: A new password must be at least 6 characters long and can not contain spaces.

# User

There are two ways of changing password:

* via UI interface,
* using bash script,
* to send GET request via Graylog REST API.

## Change user password using bash command

If you have access to host machine of Graylog, you can use this way. There is a script `change-password.sh` on the host
machine. How to use the script described [above](#change-root-user-password).

Note: actually, for non-root user the script sends REST request to change password.

## Change user password via Graylog REST API

To change user password you need to know it\`s id that consists of 24 symbols (`[a-z0-9]`). It can be found in url
in browser on user\`s page or if you have grants you can get it by GET request `http://<host>/api/users`.
To send request you can be authorized as user you want to change.

```bash
PUT https://<host>/api/users/<user_id>/password
```

Headers:

```text
Content-Type: application/json
X-Requested-By: Graylog API Browser
```

Json body:

```json
{
    "password": "new_password",
    "old_password": "old_password"
}
```

Successful response code is 204. It means that the password was successfully updated and user must make all next
actions with the new password.
According to Graylog API Browser there are possible error status codes:

* 400 - The new password is missing, or the old password is missing or incorrect.
* 403 - The requesting user has insufficient privileges to update the password for the given user.
* 404 - User does not exist.
