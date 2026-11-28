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
| `member` | basename of `dest` | Filename pattern of the binary inside an archive. It must match exactly one file. |
| `archive` | from the filename | Whether to unpack the download. `.tar.gz`, `.tgz`, `.tar`, and `.zip` count as archives. |
| `checksum` | none | Checksum of the download, such as `sha256:<hex>`, as `get_url` takes it. |
| `owner`, `group` | `root` | Owner and group of the installed binary. |
| `mode` | `0755` | Mode of the installed binary. |

Every run downloads into a new directory under the temporary directory and removes it at the end, even when a task
fails. If the host becomes unreachable during the run, Ansible cannot remove the directory, but no later run reads it.
The role then copies the binary to `dest` when its content differs, or sets the owner, group, or mode when only those
differ. `artifact_fetch_result` is changed in both cases, so the example above also restarts the service after the
role fixes only the owner or mode.

A missing `dest` directory is created with mode `0755`. An existing one keeps its owner and mode.

In check mode the role still downloads and unpacks into the staging directory, which it then removes, so
`artifact_fetch_result` shows whether a real run would change `dest`.

## Artifact server settings

| Variable | Default | Description |
| --- | --- | --- |
| `observability_artifacts_url` | `""` | Base URL for `url` values that are paths, such as a mirror of GitHub releases. A value without a scheme counts as `https://`. |
| `observability_artifacts_username`, `observability_artifacts_password` | `""` | Basic auth credentials. The role sends them only when both are set. |
| `observability_artifacts_validate_certs` | `true` | Check the server certificate. |
| `observability_artifacts_ca_file` | `""` | Path on the host to the CA of the server. It replaces the system trust store for the download. |
| `artifact_fetch_timeout` | `60` | Seconds that one request may wait for the server, such as to connect or for the next data. A slow response that keeps sending data can take longer. |
| `artifact_fetch_retries` | `5` | Number of retries after a failed download, 2 seconds apart. |

The credentials, `observability_artifacts_validate_certs`, and `observability_artifacts_ca_file` apply only to URLs
with the origin of `observability_artifacts_url`: the same scheme, host, and port. A download from another origin,
such as a full GitHub URL, sends no credentials and checks the certificate against the system trust store.

Task names and role messages show the URL without user information or a query string. A failed download still
prints the module's own result, which includes the full URL, so put credentials in
`observability_artifacts_username` and `observability_artifacts_password`, not in the URL.

The old `raw_artifacts_registry*` names still work; `vars/deprecated.yml` lists them.

`observability_artifacts_validate_certs` defaults to `true`, while the old `raw_artifacts_registry_validate_certs`
defaulted to `false` in the `common` role. An inventory that relied on that default for a server with a self-signed
certificate needs one of these:

- the CA in the system trust store of the managed host;
- `observability_artifacts_ca_file` pointing to the CA on the managed host;
- `observability_artifacts_validate_certs: false`.

The role reads `observability_artifacts_ca_file` and the old `raw_artifacts_registry_ca_cert_file` on the managed
host. The `common` role copied that file from `ssl_module_files_path` on the controller; the caller now has to place
it on the host first.
