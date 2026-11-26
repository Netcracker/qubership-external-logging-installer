# host_prepare

Prepares a host for any stack in the collection. Run it first in every play:

```yaml
- hosts: victorialogs
  become: true
  roles:
    - qubership.observability.host_prepare
    - qubership.observability.container_runtime
```

## Preflight checks

- Warns when the OS is not Ubuntu 20.04–24.04 or RHEL, Rocky, or Oracle Linux 8–9.
- Warns when the inventory sets an old variable name. Every role lists its old names in `vars/deprecated.yml`.
- Stops when the host has data from an earlier install in a directory that the data directory setting no longer
  points to, because the stack would start with empty data. The message names the `observability_data_dir` value
  that keeps the old data. Set `host_prepare_check_legacy_data: false` only after moving the data.

Run only the checks with `tasks_from: preflight`.

## Settings

| Variable | Default | Description |
| --- | --- | --- |
| `observability_data_dir` | `/var/lib/observability` | Data root. Each stack uses a subdirectory, such as `graylog` or `victorialogs`. |
| `observability_config_dir` | `/etc/observability` | Config root, including the TLS directory. |
| `host_prepare_sysctl` | `fs.file-max` and `vm.max_map_count` | Kernel settings, written to `/etc/sysctl.d/90-observability.conf`. |
| `host_prepare_limits` | `nofile` 260000 and `nproc` 32766 for all users | Entries for `/etc/security/limits.conf`. |
| `host_prepare_exporters_user`, `host_prepare_exporters_group` | `monitoring_exporters` | System user and group for the exporters. |
| `host_prepare_ntp_servers` | `[]` | NTP servers for chrony, as a list or a comma-separated string. Empty leaves time settings alone. |
| `host_prepare_system_info` | `true` | Print OS, hardware, and network facts. |

## TLS certificate

The role installs one certificate per host for the proxies of every stack:
`<observability_config_dir>/tls/<host_prepare_tls_name>.crt` and `.key`, with the key in mode `0600`. Point the
proxies at these two files, and with `existing`, place the files there before the run.

| Variable | Default | Description |
| --- | --- | --- |
| `host_prepare_tls_name` | `ansible_host`, or `inventory_hostname` when `ansible_host` is not set | Base name of the two files. |
| `host_prepare_tls_san` | `ansible_host` and `inventory_hostname` | Names in the self-signed certificate. The first is the common name. An IPv4 or IPv6 address becomes an `IP:` entry, anything else a `DNS:` entry. |
| `host_prepare_tls_selfsigned_days` | `3650` | Validity of the self-signed certificate in days. |

| `observability_tls_cert_source` | What the role does |
| --- | --- |
| `none` (default) | Nothing. |
| `selfsigned` | Creates a 4096-bit RSA key and a certificate for `host_prepare_tls_san`, valid for `host_prepare_tls_selfsigned_days`. |
| `content` | Writes `host_prepare_tls_cert_content` and `host_prepare_tls_key_content`, both PEM text and both required. Keep them in a vault. |
| `local_file` | Copies `host_prepare_tls_cert_file` and `host_prepare_tls_key_file`, both paths on the controller and both required. |
| `existing` | Checks that both files are already on the host, and stops when one is missing. |

The old V names, such as `global_ssl_cert_source` and `global_data_dir`, still work.
