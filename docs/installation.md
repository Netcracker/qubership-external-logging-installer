This document provides information about the requirements, configuration, and steps to install Logging on the VM.

# Table of Content

* [Table of Content](#table-of-content)
* [Prerequisites](#prerequisites)
  * [Supported OS](#supported-os)
  * [Hardware Requirements](#hardware-requirements)
  * [Storage Requirements](#storage-requirements)
  * [Software Requirements](#software-requirements)
  * [Security Requirements](#security-requirements)
* [Best practices and recommendations](#best-practices-and-recommendations)
  * [HWE](#hwe)
  * [Usage of extended variables](#usage-of-extended-variables)
* [Parameters](#parameters)
  * [Common](#common)
  * [System](#system)
  * [Docker](#docker)
  * [Graylog](#graylog)
  * [Graylog Migration](#graylog-migration)
  * [Graylog Stream Settings](#graylog-stream-settings)
  * [Graylog Auth Proxy](#graylog-auth-proxy)
  * [TLS](#tls)
  * [Common exporters](#common-exporters)
  * [Graylog metrics](#graylog-metrics)
  * [MongoDB Exporter](#mongodb-exporter)
  * [OpenSearch Exporter](#opensearch-exporter)
  * [Node Exporter](#node-exporter)
  * [cAdvisor Exporter](#cadvisor-exporter)
  * [FluentD](#fluentd)
  * [FluentBit](#fluentbit)
* [Post Installation Steps](#post-installation-steps)
  * [Configuring URL whitelist](#configuring-url-whitelist)

# Prerequisites

This section provides prerequisites to install Logging on the VM.

## Supported OS

* apt based:
  * Ubuntu 22.04 LTS (**recommended**)
  * Ubuntu 20.04 LTS
* yum/dfn based:
  * CentOS 8.x
  * RHEL 8.x
  * Oracle Linux 8.x
  * Amazon Linux 2
  * Rocky Linux 8.6+
  * Rocky Linux 9.2, 9.3

**Note:** If you want to install Logging on VM using version `< 0.11.x` you need to disable prerequisites
check:

```yaml
all:
  hosts:
    ...
  vars:
    check_prerequisites_enabled: false   # <-- set this parameter
```

If you use the installer `>= 0.11.x` if can ignore it note.

[Back to TOC](#table-of-content)

## Hardware Requirements

* CPU - 4+ vCPU
* RAM - 8+ GB
* HDD - 1000+ IOPS required for optimum performance
* Opened ports:
  * `22` - SSH port
  * `80` - Redirect on Graylog Web UI to HTTPS
  * `443` - Graylog Web UI
  * `514` - Default Graylog port for Syslog UDP input
  * `12201` - Default Graylog port for GELF TCP input
  * `12202` - Default Graylog port for GELF UDP input
* Other ports if you plan additional IGraylog inputs

[Back to TOC](#table-of-content)

## Storage Requirements

Graylog using OpenSearch/ElasticSearch to store and search by logs. OpenSearch/ElasticSearch provides increased
requirements for storage type, throughput and speed.

You **never** should select NFS or NFS-based (AWS EFS and so on) storages for OpenSearch/ElasticSearch.

General recommendation:

* IOPS - 1000+
* Throughput - 50+ MB/s
* Disk type - recommended use SSD

Also, we recommend planning your deployment with two separate devices for:

* Graylog journald cache
* OpenSearch storage

[Back to TOC](#table-of-content)

## Software Requirements

The next tools must be installed before running the Logging installation:

* `docker.io` (**supported >= 20.x only**)
* `python3`
* `python3-pip` (if using python < 3.4, or `pip` was not installed)
* `python3-docker`
* `acl`
* `zip`
* `unzip`
* `net-tools`

**Note:** Python3 is highly recommended. Python requirements specified for Python3.
Python2 has been out of support since the 2020 year [https://www.python.org/doc/sunset-python-2](https://www.python.org/doc/sunset-python-2).

**Warning!** Graylog base image based on `Ubuntu 22.04` base image.
And this image can be run using a Docker strictly version **>= 20.x**! Some links that explain why:

* [https://community.graylog.org/t/upgrading-from-4-3-3/25926/7](https://community.graylog.org/t/upgrading-from-4-3-3/25926/7)
* [https://github.com/adoptium/containers/issues/215#issuecomment-1142046045](https://github.com/adoptium/containers/issues/215#issuecomment-1142046045)
* [https://stackoverflow.com/questions/72841549/container-fails-to-start-insufficient-memory-for-the-java-runtime-environment-t](https://stackoverflow.com/questions/72841549/container-fails-to-start-insufficient-memory-for-the-java-runtime-environment-t)

**Do not try** to use the older Docker versions (older than < 20.x) with Graylog > 4.3.3!

[Back to TOC](#table-of-content)

## Security Requirements

Ensure that the `ansible_user` used for deployment has the root privilege and is included in the **sudoers**
list on the target VM (this permission is necessary only for the installation procedure).

[Back to TOC](#table-of-content)

# Best practices and recommendations

## HWE

The following major parameters are subject to adjustment according to the desired throughput:

* Count CPU on VM
* Graylog server RAM
* Elasticsearch RAM

The following table shows the typical throughput/HWE ratio:

<!-- markdownlint-disable line-length -->
| Input logs, msg/sec                        | `<1000` | `1000-3000` | `5000-7500` | `7500-10000` | `10000-15000` | `15000-25000` | `>25000` |
| ------------------------------------------ | ------- | ----------- | ----------- | ------------ | ------------- | ------------- | -------- |
| CPU                                        | 4       | 6           | 8           | 8            | 12            | 12            | 16+      |
| ES heap, Gb                                | 2       | 4           | 8           | 8            | 8             | 12            | 16+      |
| Graylog heap, Gb                           | 1       | 2           | 2           | 4            | 4             | 6             | 6        |
| Basic RAM (Mongo, Nginx, Telegraf, OS), Gb | 1       | 2           | 2           | 2            | 2             | 2             | 2        |
| Total RAM, Gb                              | 6       | 8           | 12          | 16           | 16            | 22            | 24+      |
| HDD volume, 1/day (very rough)             | <80 Gb  | 80-200 Gb   | 300-600 Gb  | 600-800 Gb   | 0.8-1 Tb      | 1-2 Tb        | 2+ Tb    |
| Disk speed, Mb/s                           | 2       | 5           | 10          | 20           | 30            | 50            | 100      |
<!-- markdownlint-enable line-length -->

**Notes**:

* For values such as "4-6", the minimum number is enough to start processing the stated throughput
  and work with the system. However, there is a possibility that the UI may sometimes be temporarily slow.
  Also, payload peaks can impact the system response time. The maximum number is the value to work comfortably
  even with some reserve.
* The throughput listed in the table is an average throughput over a long period.
  The system is able to handle one, two, or three times larger payloads without performance degradation and outage,
  but not for a long time. Thus, unexpected payload peaks are not a problem.
* The concrete payload is dependent on applications in the cloud and their log-level configurations.

## Usage of extended variables

You can specify extended variables which provided path for ansible variables:

* `GROUP_VARS` - allow to specify path to file with ansible group vars, which be copied to the `/ci/ansible/group_vars;
* `HOSTS_FILE` - allow to specify standard `hosts` file for ansible, which be copied to `/ci/ansible/hosts`;
* `HOSTS_VARS` - allow to specify path to file with ansible hosts vars, which be copied to the `/ci/ansible/hosts_vars`;
* `KEY_VAR` - allow to specify private `.pem` key;
* `EXTRA_VARS` - allow to set extra vars for current playbook;
* `ansible_limit` - allow to specify further limit selected hosts to an additional pattern.

**Notes**:

* [More information about inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
* [More information about standard flags of `ansible-playbook` command](https://docs.ansible.com/ansible/latest/cli/ansible-playbook.html)

[Details](/templates/README.md)

[Back to TOC](#table-of-content)

# Parameters

Currently, Ansible scripts to install Logging on the VM using Ansible inventory in YAML format.
Official Ansible documentation on how to build and work with inventory:

* [How to build your inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
* [Uses a specific YAML file as an inventory source](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/yaml_inventory.html)

It means that all parameters described below will be specified in the following format:

```yaml
all:
  hosts:
    <host_ip>:
      ansible_user: <ssh_user_name>
  vars:
    <parameter_1>
    <parameter_2>
    ...
    <parameter_N>
```

For example:

```yaml
all:
  hosts:
    1.2.3.4:
      ansible_user: ubuntu
  vars:
    graylog_install: True
    ...
```

[Back to TOC](#table-of-content)

## Common

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    raw_artifacts_registry: ...
```

<!-- markdownlint-disable line-length -->
| Parameter                               | Type    | Mandatory | Default value | Description                                           |
| --------------------------------------- | ------- | --------- | ------------- | ----------------------------------------------------- |
| `raw_artifacts_registry`                | string  | no        | `-`           | Default registry for raw artifacts                    |
| `raw_artifacts_registry_validate_certs` | boolean | no        | `false`       | Enable raw registry certificate validation            |
| `raw_artifacts_registry_ca_cert_file`   | string  | no        | `-`           | Name of CA certificate                                |
| `raw_artifacts_registry_username`       | string  | no        | `-`           | The username for authorization on the raw registry    |
| `raw_artifacts_registry_password`       | string  | no        | `-`           | The password for authorization on the raw registry    |
| `docker_registry`                       | string  | no        | `-`           | Default docker registry                               |
| `docker_registry_username`              | string  | no        | `-`           | The username for authorization on the docker registry |
| `docker_registry_password`              | string  | no        | `-`           | The password for authorization on the docker registry |
| `docker_registry_validate_certs`        | boolean | no        | `false`       | Enable docker registry certificate validation         |
| `docker_registry_ca_cert_file`          | string  | no        | `-`           | Name of CA certificate                                |
| `docker_container_timeout`              | integer | no        | `300`         | Set image pulling and container starting timeouts     |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    raw_artifacts_registry: nexus.test.org/raw
    docker_registry: nexus.test.org:17001
```

[Back to TOC](#table-of-content)

## System

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    check_prerequisites_enabled: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                     | Type    | Mandatory | Default value | Description                                                                                                                                                |
| ----------------------------- | ------- | --------- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `check_prerequisites_enabled` | string  | no        | `true`        | Enable checking of target VM on HW requirements compliance (such as enough CPU, RAM, HDD or opened ports)                                                  |
| `graylog_heap_size_mb`        | integer | no        | `2048`        | Set minimal RAM size for Graylog heap. Sum of `graylog_heap_size_mb` and `elasticsearch_heap_size_mb` should be less or equal VM RAM size                  |
| `elasticsearch_heap_size_mb`  | integer | no        | `2048`        | Set minimal RAM size for OpenSearch/ElasticSearch heap. Sum of `graylog_heap_size_mb` and `elasticsearch_heap_size_mb` should be less or equal VM RAM size |
| `ntp_server`                  | string  | no        | `-`           | The NTP server address or comma separated addresses                                                                                                        |
| `filesystem_mount_enabled`    | string  | no        | `false`       | **DEPRECATED** Enable file system creation on block device and mount disk to Graylog data directory                                                        |
| `install_thirdparty`          | string  | no        | `false`       | **DEPRECATED** Enable install third-party packages required for Graylog                                                                                    |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    check_prerequisites_enabled: true
    graylog_heap_size_mb: 2048
    elasticsearch_heap_size_mb: 2048

    # Time sync settings
    ntp_server: 1.2.3.4,1.2.3.5

    # Deprecated
    filesystem_mount_enabled: false
    install_thirdparty: false
```

[Back to TOC](#table-of-content)

## Docker

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    change_docker_network_allowed: false
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                       | Type   | Mandatory | Default value   | Description                                                                                                                                      |
| ------------------------------- | ------ | --------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `change_docker_network_allowed` | string | no        | `false`         | Enable default bridge in the Docker containers so that protection from vulnerabilities is increased                                              |
| `docker_bridge0_ipaddr`         | string | no        | `192.168.5.1`   | The static IP-address. If `change_docker_network_allowed` is set to `true`, it uses Bridge0 network instead of Docker0 with this IP address      |
| `docker_bridge0_netmask`        | string | no        | `255.255.255.0` | If `change_docker_network_allowed` is set to `true`, it uses Bridge0 network instead of Docker0 with this network mask                           |
| `docker_pids_limit`             | string | no        | `4096`          | The PIDs limit. The number to limit the running processes at a time. It is strongly recommended to set this value                                |
| `docker_threads_soft_limit`     | string | no        | `-`             | The number to limit the threads used by processes at a time, exceeding this limit causes warnings                                                |
| `docker_threads_hard_limit`     | string | no        | `-`             | The number to limit the threads used by processes at a time, it cannot be exceeded. This limit should be greater than or equal to the soft limit |
<!-- markdownlint-enable line-length -->

**Warning!** The `change_docker_network_allowed`, `docker_bridge0_ipaddr`, and `docker_bridge0_netmask`
parameters can be applied only in the first installation or in case of an update from docker0 to bridge0.
In other cases, these parameters do not change.

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    change_docker_network_allowed: true
    docker_bridge0_ipaddr: 192.168.5.1
    docker_bridge0_netmask: 255.255.255.0
    docker_pids_limit: 4096
    docker_threads_soft_limit: 2048
    docker_threads_hard_limit: 4096
```

[Back to TOC](#table-of-content)

## Graylog

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    graylog_install: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                    | Type    | Mandatory | Default value                         | Description                                                                                                                                                                                                |
| ---------------------------- | ------- | --------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `graylog_install`            | boolean | no        | `True`                                | Enable/disable graylog installation: `True` to install, `False` to uninstall                                                                                                                               |
| `graylog_image`              | string  | no        | `graylog/graylog:5.1.3`               | Docker image of Graylog                                                                                                                                                                                    |
| `nginx_image`                | string  | no        | `nginx:1.25.2-alpine`                 | Docker image of Nginx                                                                                                                                                                                      |
| `mongo_image`                | string  | no        | `mongo:5.0.19`                        | Docker image of MongoDB                                                                                                                                                                                    |
| `opensearch_image`           | string  | no        | `opensearchproject/opensearch:1.3.12` | Docker image of OpenSearch                                                                                                                                                                                 |
| `root_password`              | string  | no        | `admin`                               | The password for the super admin user on Graylog                                                                                                                                                           |
| `auditviewer_password`       | string  | no        | `auditViewer`                         | The initial password of `auditViewer` user                                                                                                                                                                 |
| `operator_password`          | string  | no        | `operator`                            | The initial password of `operator` user                                                                                                                                                                    |
| `telegraf_operator_password` | string  | no        | `telegraf_operator`                   | The initial password of `telegraf_operator` user                                                                                                                                                           |
| `graylog_volume`             | string  | no        | `/var/lib`                            | The folder on the target VM that is used for deployment and data storage                                                                                                                                   |
| `graylog_heap_size_mb`       | string  | no        | `2048`                                | The heap size for Graylog in Mb, for example: `2048` or `4096`                                                                                                                                             |
| `additional_graylog_volumes` | string  | no        | `-`                                   | The list of additional volumes for the Graylog docker container. The values equivalent to the usual docker volume record `/var/lib/graylog/certs:/usr/share/graylog/data/certs:z` and separated by a comma |
| `additional_graylog_ports`   | string  | no        | `-`                                   | The list of additional thrown ports for the Graylog docker container. The values equivalent to the usual docker thrown ports record `570`, `590:590`, `600:600/tcp` and separated by a comma               |
| `content_deploy_policy`      | string  | no        | `only-create`                         | The Graylog content deploy policy (such as streams, inputs, grok patterns). Possible values: `only-create`, `force-update`, `skip`                                                                         |
| `dns_name`                   | string  | no        | `-`                                   | The address by which Graylog is accessible to users (DNS name). If this value is set, then Graylog is not accessible by its IP address                                                                     |
| `index_replicas`             | integer | no        | `0`                                   | The number of OpenSearch/ElasticSearch replicas used per index                                                                                                                                             |
| `index_shards`               | integer | no        | `1`                                   | The number of OpenSearch/ElasticSearch shards used per index                                                                                                                                               |
| `path_repo`                  | string  | no        | `archives`                            | The name of directory in OpenSearch/ElasticSearch for saving snapshots                                                                                                                                     |
<!-- markdownlint-enable line-length -->

The parameter `content_deploy_policy` has the following possible values and these policies mean:

* `only-create` - only creation of missing content, without updating the existing content
* `force-update` - forcibly updating out-of-the-box content, if the content does not exist, it is created
* `skip` - skip all content create/update tasks

**Warning!** Parameters `index_replicas: 0` and `index_shards: 1` will apply only for new IndexSets / Indices.
Please plan your deployment.

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    graylog_install: true
    graylog_volume: /srv/docker/graylog
    graylog_heap_size_mb: 2048
    additional_graylog_volumes: /srv/docker/graylog/graylog/certs:/usr/share/graylog/data/certs:z,/srv/docker/graylog/graylog/test:/usr/share/graylog/data/test:z
    additional_graylog_ports: 590:590,600:600/tcp
    content_deploy_policy: only-create
    dns_name: grasylog.test.org
    index_replicas: 0
    index_shards: 1
    path_repo: archives

    # Passwords for in-built users
    root_password: admin
    auditviewer_password: auditViewer
    operator_password: operator
    telegraf_operator_password: telegraf_operator
```

[Back to TOC](#table-of-content)

## Graylog Migration

The parameter that can be used for migration from `Graylog 4.x` (with `MongoDB 3.6.x` and `ElasticSearch 6.8.x`)
to `Graylog 5.x` (with `MongoDB 5.x` and `OpenSearch 1.x`).

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    mongo_upgrade: true
    ...
```

**Warning!** Parameters for migration for MongoDB and from ElasticSearch to OpenSearch must be set
**only for migration**. After migration will complete successfully you **must remove** these parameters.

<!-- markdownlint-disable line-length -->
| Parameter               | Type    | Mandatory | Default value | Description                                                      |
| ----------------------- | ------- | --------- | ------------- | ---------------------------------------------------------------- |
| `mongo_upgrade`         | boolean | no        | `false`       | Activates automatic step-by-step upgrade of the MongoDB database |
| `migrate_to_opensearch` | boolean | no        | `false`       | Moves all stored data from ElasticSearch to OpenSearch           |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    mongo_upgrade: true
    migrate_to_opensearch: true
```

[Back to TOC](#table-of-content)

## Graylog Stream Settings

Parameter to configure rotation strategies for all in-built Streams.

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    system_logs_install: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                          | Type    | Mandatory | Default value | Description                                                    |
| ---------------------------------- | ------- | --------- | ------------- | -------------------------------------------------------------- |
| `system_logs_install`              | boolean | no        | `true`        | Install a logs stream                                          |
| `system_rotation_strategy`         | string  | no        | `sizeBased`   | Rotation strategy, possible values: `sizeBased` or `timeBased` |
| `system_rotation_period`           | string  | no        | `-`           | Rotation period for `timeBased` strategy                       |
| `audit_logs_install`               | boolean | no        | `true`        | Install a logs stream                                          |
| `audit_rotation_strategy`          | string  | no        | `sizeBased`   | Rotation strategy, possible values: `sizeBased` or `timeBased` |
| `audit_rotation_period`            | string  | no        | `-`           | Rotation period for `timeBased` strategy                       |
| `access_logs_install`              | boolean | no        | `false`       | Install a logs stream                                          |
| `access_rotation_strategy`         | string  | no        | `timeBased`   | Rotation strategy, possible values: `sizeBased` or `timeBased` |
| `access_rotation_period`           | string  | no        | `P1M`         | Rotation period for `timeBased` strategy                       |
| `integration_logs_install`         | boolean | no        | `false`       | Install a logs stream                                          |
| `integration_rotation_strategy`    | string  | no        | `timeBased`   | Rotation strategy, possible values: `sizeBased` or `timeBased` |
| `integration_rotation_period`      | string  | no        | `P1M`         | Rotation period for `timeBased` strategy                       |
| `nginx_logs_install`               | boolean | no        | `false`       | Install a logs stream                                          |
| `nginx_rotation_strategy`          | string  | no        | `timeBased`   | Rotation strategy, possible values: `sizeBased` or `timeBased` |
| `nginx_rotation_period`            | string  | no        | `P1M`         | Rotation period for `timeBased` strategy                       |
| `k8s_events_install`               | boolean | no        | `false`       | Install a logs stream                                          |
| `k8s_events_rotation_strategy`     | string  | no        | `timeBased`   | Rotation strategy, possible values: `sizeBased` or `timeBased` |
| `k8s_events_rotation_period`       | string  | no        | `P1M`         | Rotation period for `timeBased` strategy                       |
| `k8s_events_max_size`              | integer | no        | 1073741824    | Max index size of index for `sizeBased` strategy               |
| `k8s_events_max_number_of_indices` | integer | no        | 5             | Number of indices in index set                                 |
<!-- markdownlint-enable line-length -->

**Note:** Rotation periods are presented as
[ISO 8601 Duration](https://www.ionos.com/digitalguide/websites/web-development/iso-8601/).

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    system_logs_install: true
    system_logs_rotation_strategy: "sizeBased"
    system_logs_rotation_period: "P1M"

    audit_logs_install: true
    audit_logs_rotation_strategy: "sizeBased"
    audit_logs_rotation_period: "P1M"

    integration_logs_install: false
    integration_logs_rotation_strategy: "timeBased"
    integration_logs_rotation_period: "P1M"

    access_logs_install: false
    access_logs_rotation_strategy: "timeBased"
    access_logs_rotation_period: "P1M"

    nginx_logs_install: false
    nginx_logs_rotation_strategy: "timeBased"
    nginx_logs_rotation_period: "P1M"

    k8s_events_install: true
    k8s_events_rotation_strategy: "timeBased"
    k8s_events_rotation_period: "P1M"
```

[Back to TOC](#table-of-content)

## Graylog Auth Proxy

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    graylog_auth_proxy_enabled: false
    ...
```

Common parameters:

<!-- markdownlint-disable line-length -->
| Parameter                             | Type    | Mandatory | Default value | Description                                                                                                       |
| ------------------------------------- | ------- | --------- | ------------- | ----------------------------------------------------------------------------------------------------------------- |
| `graylog_auth_proxy_enabled`          | boolean | no        | `false`       | Enable installation of graylog-auth-proxy                                                                         |
| `graylog_auth_proxy_log_level`        | string  | no        | `INFO`        | Logging level. Allowed values: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`                                    |
| `graylog_auth_proxy_requests_timeout` | float   | no        | `30`          | A global timeout parameter affects requests to LDAP server, OAuth server and Graylog server                       |
| `graylog_auth_proxy_auth_type`        | string  | no        | `ldap`        | Defines which type of authentication protocol will be chosen (LDAP or OAuth 2.0). Allowed values: `ldap`, `oauth` |
| `htpasswd`                            | string  | no        | `-`           | Path to `htpasswd` file with LDAP password for the bind DN or OAuth Client Secret in base64 format                |
<!-- markdownlint-enable line-length -->

Parameters for integration with LDAP:

<!-- markdownlint-disable line-length -->
| Parameter        | Type    | Mandatory | Default value          | Description                                        |
| ---------------- | ------- | --------- | ---------------------- | -------------------------------------------------- |
| `ldap_start_tls` | boolean | no        | `false`                | Enable establishing a `STARTTLS` protected session |
| `ldap_over_ssl`  | boolean | no        | `false`                | Establish an LDAP session over SSL                 |
| `ldap_url`       | string  | yes       | `ldap://localhost:389` | LDAP host to query                                 |
| `base_dn`        | string  | yes       | `-`                    | LDAP base DN                                       |
| `bind_dn`        | string  | yes       | `-`                    | LDAP bind DN                                       |
| `bind_password`  | string  | no        | `-`                    | LDAP password for the bind DN                      |
| `ldap_filter`    | string  | no        | `(cn=%(username)s)`    | LDAP filter                                        |
<!-- markdownlint-enable line-length -->

Parameters for integration with OAuth authorization server:

<!-- markdownlint-disable line-length -->
| Parameter                  | Type   | Mandatory | Default value           | Description                                                                                                                                                                                                                                |
| -------------------------- | ------ | --------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `oauth_host`               | string | yes       | `-`                     | OAuth2 authorization server host                                                                                                                                                                                                           |
| `oauth_authorization_path` | string | yes       | `-`                     | This path will be used to build URL for redirection to OAuth2 authorization server login page                                                                                                                                              |
| `oauth_token_path`         | string | yes       | `-`                     | This path will be used to build URL for getting access token from OAuth2 authorization server                                                                                                                                              |
| `oauth_userinfo_path`      | string | yes       | `-`                     | This path will be used to build URL for getting information about current user from OAuth2 authorization server to get username and entities (roles, groups, etc.) for Graylog roles and streams mapping                                   |
| `oauth_redirect_uri`       | string | yes       | `-`                     | URI to redirect after successful logging in on the OAuth2 authorization server-side. Must have the following format: `http(-s)://<VM-host-or-IP>/code`. Please make sure that your OAuth server allows using this URI as a redirection URI |
| `oauth_client_id`          | string | yes       | `-`                     | OAuth2 Client ID for the proxy                                                                                                                                                                                                             |
| `oauth_client_secret`      | string | no        | `-`                     | OAuth2 Client Secret for the proxy                                                                                                                                                                                                         |
| `oauth_scopes`             | string | no        | `openid profile roles`  | OAuth2 scopes for the proxy separated by spaces. Configured for Keycloak server by default                                                                                                                                                 |
| `oauth_user_jsonpath`      | string | no        | `preferred_username`    | JSONPath (by jsonpath-ng) for taking username from the JSON returned from OAuth2 server by using userinfo path. Configured for Keycloak server by default                                                                                  |
| `oauth_roles_jsonpath`     | string | no        | `realm_access.roles[*]` | JSONPath (by jsonpath-ng) for taking information about entities (roles, groups, etc.) for Graylog roles and streams mapping from the JSON returned from OAuth2 server by using userinfo path. Configured for Keycloak server by default    |
<!-- markdownlint-enable line-length -->

TLS parameters for LDAP or OAuth provider:

<!-- markdownlint-disable line-length -->
| Parameter                        | Type    | Mandatory | Default value | Description                                                                                                        |
| -------------------------------- | ------- | --------- | ------------- | ------------------------------------------------------------------------------------------------------------------ |
| `graylog_auth_proxy_skip_verify` | boolean | no        | `false`       | Allow skipping verification of the LDAP or OAuth server's certificate                                              |
| `graylog_auth_proxy_ca_file`     | string  | no        | `-`           | CA certificate file (`.crt`) that is presented on Deploy VM from the `certificates.zip` ZIP archive                |
| `graylog_auth_proxy_cert_file`   | string  | no        | `-`           | SSL certificate file (`.crt`) that is presented on Deploy VM from the `certificates.zip` ZIP archive               |
| `graylog_auth_proxy_key_file`    | string  | no        | `-`           | SSL certificate key file (`.pem` or `.key`) that is presented on Deploy VM from the `certificates.zip` ZIP archive |
<!-- markdownlint-enable line-length -->

Graylog parameters:

<!-- markdownlint-disable line-length -->
| Parameter                  | Type    | Mandatory | Default value                                                                      | Description                                                                                |
| -------------------------- | ------- | --------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `role_mapping`             | string  | no        | `[]`                                                                               | Filter for mapping Graylog roles between LDAP or OAuth service and Graylog users           |
| `stream_mapping`           | string  | no        | `-`                                                                                | Filter for sharing Graylog streams between LDAP or OAuth service and Graylog users         |
| `pre_created_users`        | string  | no        | `admin,auditViewer,operator,telegraf_operator,graylog-sidecar,graylog_api_th_user` | Comma separated pre-created users in Graylog for which you do not need to rotate passwords |
| `passwd_rotation_interval` | integer | no        | `3`                                                                                | Interval in days between password rotation for non-pre-created users                       |
<!-- markdownlint-enable line-length -->

If you want to use the proxy, please be ensure that you set each parameter for the correct work.

Examples:

**Note:** It's just examples of a parameter's format, not recommended parameters.

Integration with LDAP:

```yaml
all:
  vars:
    graylog_auth_proxy_enabled: true
    graylog_auth_proxy_auth_type: ldap
    ldap_url: ldap://openldap.test.org:636
    base_dn: cn=admin,dc=example,dc=com
    bind_dn: dc=example,dc=com
    bind_password: password
    ldap_filter: (cn=%(username)s)
    role_mapping: '"CN=otrk_admins,OU=OTRK_Groups,OU=IRQA_LDAP,DC=testad,DC=local":["Admin"] | ["Reader"]'
    stream_mapping: '"CN=otrk_admins,OU=OTRK_Groups,OU=IRQA_LDAP,DC=testad,DC=local":["All messages/manage","all events/view"] | "CN=otrk_users,OU=OTRK_Groups,OU=IRQA_LDAP,DC=testad,DC=local":["All events"] | ["System logs/view"]'
    pre_created_users: admin,auditViewer,operator,telegraf_operator,graylog-sidecar,graylog_api_th_user
    passwd_rotation_interval: 3  # days
```

Integration with OAuth authorization server:

```yaml
all:
  vars:
    graylog_auth_proxy_enabled: true
    graylog_auth_proxy_auth_type: oauth
    oauth_host: http://mykeycloak.com
    oauth_authorization_path: /realms/myrealm/protocol/openid-connect/auth
    oauth_token_path: /realms/myrealm/protocol/openid-connect/token
    oauth_userinfo_path: /realms/myrealm/protocol/openid-connect/userinfo
    oauth_redirect_uri: http://x.x.x.x/code
    oauth_client_id: graylog-auth-proxy
    oauth_client_secret: secret
    oauth_scopes: "openid profile roles"
    oauth_user_jsonpath: "preferred_username"
    oauth_roles_jsonpath: "realm_access.roles[*]"
    ldap_filter: (cn=%(username)s)
    role_mapping: '"test_admin_role":["Admin"] | ["Reader"]'
    stream_mapping: '"test_admin_role":["All messages/manage","all events/view"] | "test_role":["All events"] | ["System logs/view"]'
    pre_created_users: admin,auditViewer,operator,telegraf_operator,graylog-sidecar,graylog_api_th_user
    passwd_rotation_interval: 3  # days
```

[Back to TOC](#table-of-content)

## TLS

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    tls_enabled: false
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter               | Type   | Mandatory | Default value      | Description                                                                                                                                                                                                                                             |
| ----------------------- | ------ | --------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tls_enabled`           | string | no        | `-`                | Enable TLS for Graylog input. The possible values are `true`/`false`                                                                                                                                                                                    |
| `certificates`          | string | yes       | `-`                | ZIP archive with custom TLS certificate files (`.crt` and `.pem` or `.key`)                                                                                                                                                                             |
| `tls_cert_file`         | string | yes       | `-`                | Graylog TLS certificate file (`.crt`) that is presented on Deploy VM from the `certificates.zip` ZIP archive or stored in repository by `ssl_module_files_path` path                                                                                    |
| `tls_key_file`          | string | yes       | `-`                | Graylog TLS certificate key file (`.pem` or `.key`) that is presented on Deploy VM from the `certificates.zip` ZIP archive or stored in repository by `ssl_module_files_path` path                                                                      |
| `tls_key_password`      | string | no        | `-`                | Graylog password for the TLS certificate key file for Graylog input                                                                                                                                                                                     |
| `ssl_certificate`       | string | yes       | `-`                | Nginx TLS certificate file (`.crt`) which is presented on the Deploy VM (relative to the directory `/tmp/`) or the certificate filename (`.crt`) from the `certificates.zip` ZIP archive or stored in repository by `ssl_module_files_path` path        |
| `ssl_certificate_key`   | string | yes       | `-`                | Nginx TLS certificate key file (`.pem`) that is presented on the Deploy VM (relative to the directory `/tmp/`) or the certificate key filename (`.pem`) from the `certificates.zip` ZIP archive or stored in repository by `ssl_module_files_path` path |
| `ssl_data_host_path`    | string | no        | `/etc/logging/ssl` | Path to store ssl certificates for registries                                                                                                                                                                                                           |
| `ssl_module_files_path` | string | no        | `-`                | Path in operations portal repository(configuration or pipeline), were are stored certificates. All files and folders which are stored in pipeline or configuration repository will be automatically mounted to module container filesystem.             |
<!-- markdownlint-enable line-length -->

[Back to TOC](#table-of-content)

## Common exporters

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    exporters_system_user: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                | Type   | Mandatory | Default value          | Description                            |
| ------------------------ | ------ | --------- | ---------------------- | -------------------------------------- |
| `exporters_system_user`  | string | no        | `monitoring_exporters` | Set one for all exporters system user  |
| `exporters_system_group` | string | no        | `monitoring_exporters` | Set one for all exporters system group |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    exporters_system_user: monitoring_exporters
    exporters_system_group: monitoring_exporters
```

[Back to TOC](#table-of-content)

## Graylog metrics

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    graylog_metrics_port: 9833
    ...
```

By default, monitoring is disabled. If you want to enable monitor, you should enable all exporters.

<!-- markdownlint-disable line-length -->
| Parameter              | Type    | Mandatory | Default value             | Description                                      |
| ---------------------- | ------- | --------- | ------------------------- | ------------------------------------------------ |
| `graylog_metrics_port` | integer | no        | `9833`                    | Port to listen calls of Graylog metrics scraping |
| `graylog_metrics_path` | string  | no        | `/api/metrics/prometheus` | Path under which to expose Graylog metrics       |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    graylog_metrics_port: 9833
    graylog_metrics_path: /api/metrics/prometheus
```

[Back to TOC](#table-of-content)

## MongoDB Exporter

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    mongodb_exporter_install: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                         | Type    | Mandatory | Default value                                                         | Description                                           |
| --------------------------------- | ------- | --------- | --------------------------------------------------------------------- | ----------------------------------------------------- |
| `mongodb_exporter_install`        | boolean | no        | `false`                                                               | Enable/disable MongoDB exporter installation          |
| `mongodb_exporter_tarball`        | string  | no        | `percona/mongodb_exporter/mongodb_exporter-0.30.0.linux-amd64.tar.gz` | Archive name with MongoDB exporter bin file           |
| `mongodb_exporter_custom_tarball` | string  | no        | `-`                                                                   | Custom path to `tar.gz` archive with MongoDB exporter |
| `mongodb_exporter_host_bin_dir`   | string  | no        | `/usr/local/bin`                                                      | Directory for store bin file and starting service     |
| `mongodb_exporter_listen_port`    | integer | no        | `9216`                                                                | Port to listen calls of metrics scraping              |
| `mongodb_exporter_metrics_path`   | string  | no        | `/metrics`                                                            | Path under which to expose metrics                    |
| `mongodb_exporter_flags`          | list    | no        | `[]`                                                                  | List of command line parameters for MongoDB exporter  |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    mongodb_exporter_install: true
    mongodb_exporter_tarball: percona/mongodb_exporter/mongodb_exporter-0.30.0.linux-amd64.tar.gz
    mongodb_exporter_custom_tarball: nexus.test.org/raw/percona/mongodb_exporter/mongodb_exporter-0.30.0.linux-amd64.tar.gz
    mongodb_exporter_host_bin_dir: /usr/local/bin
    mongodb_exporter_listen_port: 9216
    mongodb_exporter_metrics_path: /metrics
    mongodb_exporter_flags: []
```

[Back to TOC](#table-of-content)

## OpenSearch Exporter

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    elasticsearch_exporter_install: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                               | Type    | Mandatory | Default value                                                                                        | Description                                                 |
| --------------------------------------- | ------- | --------- | ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `elasticsearch_exporter_install`        | boolean | no        | `false`                                                                                              | Enable/disable ElasticSearch exporter installation          |
| `elasticsearch_exporter_tarball`        | string  | no        | `prometheus-community/elasticsearch_exporter/v1.3.0/elasticsearch_exporter-1.3.0.linux-amd64.tar.gz` | Archive name with ElasticSearch exporter bin file           |
| `elasticsearch_exporter_custom_tarball` | string  | no        | `-`                                                                                                  | Custom path to `tar.gz` archive with ElasticSearch exporter |
| `elasticsearch_exporter_host_bin_dir`   | string  | no        | `/usr/local/bin`                                                                                     | Directory for store bin file and starting service           |
| `elasticsearch_exporter_listen_port`    | integer | no        | `9114`                                                                                               | Port to listen calls of metrics scraping                    |
| `elasticsearch_exporter_metrics_path`   | string  | no        | `/metrics`                                                                                           | Path under which to expose metrics                          |
| `elasticsearch_exporter_flags`          | list    | no        | `[]`                                                                                                 | List of command line parameters for ElasticSearch exporter  |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    elasticsearch_exporter_install: true
    elasticsearch_exporter_tarball: prometheus-community/elasticsearch_exporter/v1.3.0/elasticsearch_exporter-1.3.0.linux-amd64.tar.gz
    elasticsearch_exporter_custom_tarball: nexus.test.org/raw/prometheus-community/elasticsearch_exporter/v1.3.0/elasticsearch_exporter-1.3.0.linux-amd64.tar.gz
    elasticsearch_exporter_host_bin_dir: /usr/local/bin
    elasticsearch_exporter_listen_port: 9114
    elasticsearch_exporter_metrics_path: /metrics
    elasticsearch_exporter_flags: []
```

[Back to TOC](#table-of-content)

## Node Exporter

All parameters described below should be specified under a section `vars` as the following:

```yaml
all:
  vars:
    node_exporter_install: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                            | Type    | Mandatory | Default value                                                                                                                                                 | Description                                                           |
| ------------------------------------ | ------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `node_exporter_install`              | boolean | no        | `false`                                                                                                                                                       | Allow you to enable node-exporter installation                        |
| `node_exporter_listen_port`          | integer | no        | `9100`                                                                                                                                                        | Port to listen on for web interface and telemetry                     |
| `node_exporter_telemetry_path`       | string  | no        | `/metrics`                                                                                                                                                    | Path under which to expose metrics                                    |
| `node_exporter_host_bin_dir`         | string  | no        | `/usr/local/bin`                                                                                                                                              | Default directory for store bin file and starting service             |
| `node_exporter_tarball`              | string  | no        | `prometheus/node_exporter/node_exporter-1.1.2.linux-amd64.tar.gz`                                                                                             | Archive name with node-exporter bin file                              |
| `node_exporter_custom_tarball`       | string  | no        | `-`                                                                                                                                                           | Custom path to `tar.gz` archive with node-exporter                    |
| `node_exporter_ignored_mount_points` | string  | no        | `^/(sys\|proc\|dev\|host\|etc\|rootfs/var/lib/docker/containers\|rootfs/var/lib/docker/overlay2\|rootfs/run/docker/netns\|rootfs/var/lib/docker/aufs)($$\|/)` | Regular expression with path what will be skipped for collect metrics |
| `node_exporter_flags`                | list    | no        | `[]`                                                                                                                                                          | List of command line parameters for node-exporter                     |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameter.

```yaml
all:
  vars:
    node_exporter_install: true
    node_exporter_listen_port: 9100
    node_exporter_telemetry_path: /metrics
    node_exporter_host_bin_dir: /usr/local/bin
    node_exporter_tarball: prometheus/node_exporter/node_exporter-1.1.2.linux-amd64.tar.gz
    node_exporter_custom_tarball: nexus.test.org/raw/prometheus/node_exporter/node_exporter-1.1.2.linux-amd64.tar.gz
    node_exporter_ignored_mount_points: ^/(sys\|proc\|dev\|host\|etc\|rootfs/var/lib/docker/containers\|rootfs/var/lib/docker/overlay2\|rootfs/run/docker/netns\|rootfs/var/lib/docker/aufs)($$\|/)
    node_exporter_flags: []
```

[Back to TOC](#table-of-content)

## cAdvisor Exporter

## FluentD

## FluentBit

# Post Installation Steps

## Configuring URL whitelist

After successful deploy you can configure URL whitelist.
There are certain components in Graylog which will perform outgoing HTTP requests. Among those, are event notifications
and HTTP-based data adapters.
Allowing Graylog to interact with resources using arbitrary URLs may pose a security risk. HTTP requests are executed
from Graylog servers and might therefore be able to reach more sensitive systems than an external user would have
access to, including AWS EC2 metadata, which can contain keys and other secrets, Elasticsearch and others.
It is therefore advisable to restrict access by explicitly whitelisting URLs which are considered safe. HTTP requests
will be validated against the Whitelist and are prohibited if there is no Whitelist entry matching the URL.

The Whitelist configuration is located at `System/Configurations/URL Whitelist`. The Whitelist is enabled by default.

If the security implications mentioned above are of no concern, the Whitelist can be completely disabled.
When disabled, HTTP requests will not be restricted.

Whitelist entries of type `Exact match` contain a string which will be matched against a URL by direct comparison.
If the URL is equal to this string, it is considered to be whitelisted.

Whitelist entries of type `Regex` contain a regular expression. If a URL matches the regular expression, the URL is
considered to be whitelisted. Graylog uses the Java Pattern class to evaluate regular expressions.

[Back to TOC](#table-of-content)
