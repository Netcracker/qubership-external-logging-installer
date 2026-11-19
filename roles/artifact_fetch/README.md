# artifact_fetch

Downloads a binary or an archive and installs one binary from it. Exporters and other roles that ship a plain binary
call it instead of downloading by themselves.

## `binary`

```yaml
- ansible.builtin.include_role:
    name: qubership.observability.artifact_fetch
    tasks_from: binary
  vars:
    artifact_fetch_artifact:
      url: "{{ node_exporter_tarball }}"
      dest: /usr/local/bin/node_exporter
      owner: "{{ exporters_system_user }}"
      group: "{{ exporters_system_group }}"

- name: Restart node_exporter when its binary changed
  ansible.builtin.systemd_service:
    name: node_exporter
    state: restarted
  when: artifact_fetch_result is changed
```

| Key | Default | Description |
| --- | --- | --- |
| `url` | required | Full `http://` or `https://` URL, or a path under `observability_artifacts_url`. |
| `dest` | required | Path of the installed binary. |
| `member` | basename of `dest` | File name pattern of the binary inside an archive. It must match exactly one file. |
| `archive` | from the file name | Whether to unpack the download. `.tar.gz`, `.tgz`, `.tar`, and `.zip` count as archives. |
| `checksum` | none | Checksum of the download, such as `sha256:<hex>`, as `get_url` takes it. |
| `owner`, `group` | `root` | Owner and group of the installed binary. |
| `mode` | `0755` | Mode of the installed binary. |

Every run downloads into a new directory under the temporary directory and removes it at the end, even when a task
fails. The role then copies the binary to `dest` only when its content differs, so `artifact_fetch_result` is changed
only after a real update.

## Artifact server settings

| Variable | Default | Description |
| --- | --- | --- |
| `observability_artifacts_url` | `""` | Base URL for `url` values that are paths, such as a mirror of GitHub releases. |
| `observability_artifacts_username`, `observability_artifacts_password` | `""` | Basic auth credentials. The role sends them only when both are set. |
| `observability_artifacts_validate_certs` | `true` | Check the server certificate. |
| `observability_artifacts_ca_file` | `""` | Path on the host to the CA of the server. It replaces the system trust store for the download. |
| `artifact_fetch_timeout` | `60` | Seconds that one download attempt may take. |
| `artifact_fetch_retries` | `5` | Number of retries after a failed download. |

The old `raw_artifacts_registry*` names still work; `vars/deprecated.yml` lists them.

`observability_artifacts_validate_certs` defaults to `true`, while the old `raw_artifacts_registry_validate_certs`
defaulted to `false` in the `common` role. An inventory that relied on that default for a server with a self-signed
certificate needs `observability_artifacts_ca_file`, or `observability_artifacts_validate_certs: false`.
