# container_runtime

Configures Docker or Podman on the host and gives other roles two entry points: `network` creates container networks,
and `run_container` starts a container the same way on both engines.

## Engine setup

Run the role once per play, before any role that starts containers:

```yaml
- ansible.builtin.include_role:
    name: qubership.observability.container_runtime
```

| Variable | Default | Description |
| --- | --- | --- |
| `observability_container_runtime` | `docker` | `docker` or `podman`. The role reads it as `container_runtime_engine`. |
| `container_runtime_install` | `false` | Install the engine from distribution packages. Docker is packaged only on Ubuntu and Debian. |
| `container_runtime_docker_configure` | `true` | Write `/etc/docker/daemon.json`. Turn it off when another tool manages the daemon. |
| `container_runtime_docker_log_max_size` | `50m` | Size at which Docker rotates a container's json-file log. |
| `container_runtime_docker_log_max_file` | `6` | Number of rotated log files that Docker keeps per container. |
| `container_runtime_docker_daemon_options` | `{}` | Extra `daemon.json` keys, merged over the role's keys. |
| `observability_image_registry` | `""` | Registry for images. Read as `container_runtime_registry`. |
| `container_runtime_registry_validate_certs` | `false` | When `false`, the registry is marked insecure in `daemon.json` or `registries.conf.d`. |
| `container_runtime_registry_ca_file` | `""` | Path on the host to the registry CA. The role copies it to `certs.d/<registry>/ca.crt`. |
| `container_runtime_registry_username`, `container_runtime_registry_password` | `""` | Registry login. The role logs in only when both are set. |
| `container_runtime_container_timeout` | `300` | Seconds that a container operation, such as a pull, may take. |
| `container_runtime_networks` | `[]` | Networks to create, in the format that `network` takes. |

The role owns the whole `daemon.json` file and restarts Docker only when the file changes. Its own keys are `icc: false`,
`live-restore: true`, json-file log rotation, and `insecure-registries` when the registry is not validated.

The old variable names, such as `docker_registry` and `configure_docker`, still work. `vars/deprecated.yml` lists them.

## `network`

```yaml
- ansible.builtin.include_role:
    name: qubership.observability.container_runtime
    tasks_from: network
  vars:
    container_runtime_networks:
      - logging
      - name: victorialogs
        mtu: 1400
```

Each item is a network name or a dict with `name` and optional `driver` and `mtu`.

## `run_container`

```yaml
- ansible.builtin.include_role:
    name: qubership.observability.container_runtime
    tasks_from: run_container
  vars:
    container_runtime_container:
      name: graylog_web_1
      image: "{{ nginx_image }}"
      networks:
        - name: logging
          aliases: [web]
      ports: ["443:443"]
      volumes: ["{{ nginx_config_dir }}:/etc/nginx/conf.d:ro,z"]
      read_only: true
      tmpfs: [/var/cache/nginx, /var/run]
      restart: "{{ nginx_config is changed }}"
```

`container_runtime_container` uses the option names of `community.docker.docker_container`. Only `name` and `image`
are required.

| Key | Default | Podman mapping |
| --- | --- | --- |
| `name`, `image`, `state`, `env`, `command`, `user`, `read_only`, `privileged`, `etc_hosts` | `state: started` | Same name |
| `restart_policy` | `container_runtime_default_restart_policy` (`always`) | Same name |
| `security_opts` | `container_runtime_default_security_opts` (`[no-new-privileges]`) | `security_opt` |
| `networks` | none | Names go to `network`, all aliases to `network_aliases`. `links` are ignored: containers on one network resolve each other by name. |
| `network_mode` | none | `network: [<mode>]` |
| `ports` | none | `publish` |
| `volumes` | none | `volume` |
| `entrypoint` | none | A list is joined into one string |
| `tmpfs` | none | `["/tmp:size=64m"]` becomes `{"/tmp": "size=64m"}` |
| `ulimits` | none | `"nofile:1024:2048"` becomes `"nofile=1024:2048"` |
| `capabilities` | none | `cap_add` |
| `labels` | none | `label` |
| `healthcheck` | none | `test` becomes `healthcheck`, with `CMD` or `CMD-SHELL` removed; `interval`, `timeout`, `retries`, and `start_period` become `healthcheck_*` |
| `pull` | module default | Docker only |
| `restart` | `false` | `force_restart` |
| `recreate` | `false` | Same name |
| `wait` | `true` | After the start, wait until the container is still running |
| `wait_retries` | `5` | Number of 2-second checks for `wait` |

Pass `restart: true` when a file that the container reads has changed. A container whose definition is unchanged is
left alone, so a second run reports no changes.

On Docker, network membership is compared strictly: a container is detached from networks that its definition no
longer lists.
