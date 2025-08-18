# Enable Authentication to MongoDB

* [Enable Authentication to MongoDB](#enable-authentication-to-mongodb)
  * [Supply credentials](#supply-credentials)
  * [User details](#user-details)

Graylog uses MongoDB to store configurations. In earlier versions of `external-logging-installer`, MongoDB was
installed without any access control enabled so that Graylog could connect to MongoDB without supplying credentials.
However, this is considered as security vulnerability. In order to fix this, authentication has been enabled.
Note that the access control is enabled by default and it's not possible to disable it.

## Supply credentials

`mongodb_root_username` and `mongodb_root_password` variables are used to supply admin user credentials.
Product uses default credentials (admin/admin).

`mongodb_graylog_username` and `mongodb_graylog_password` variables are used to supply graylog user credentials.
Product uses default credentials (graylog/graylog).

These parameters can be changed during deployment.

## User details

To enable access control in MongoDB container, it is necessary to have an `admin` user in `admin` database
which is also considered as `authenticationDatabase`. During fresh installation of MongoDB container, this can be
achieved by supplying `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` environment variables.
However if the MongoDB container was already running, MongoDB ignores these environment variables. In this case,
we create the admin user by using the credentials as explained above.

Next, we create another user `graylog` in `graylog` database of MongoDB with `readWrite` role. We use this user
for connection between Graylog and MongoDB
