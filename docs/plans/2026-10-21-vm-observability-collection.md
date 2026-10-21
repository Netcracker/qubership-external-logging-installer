# Plan: merge VM observability installers into one collection

Turn this repository into the Ansible collection `qubership.observability`. It replaces four
installers with one set of roles and four playbooks: Graylog, VictoriaLogs, log agents, and monitoring exporters.
VictoriaLogs supports single-node, HA, and cluster topologies. VictoriaMetrics roles ship without a playbook, ready for
later use. Internal-only content moves to a separate internal overlay repository that depends on the collection.

## Context

Source repositories and what each one contributes:

| Short name | Repository | Contributes |
| --- | --- | --- |
| Q | this repository (GitHub) | Graylog stack base, public images, CI, community files |
| L | internal logging installer (GitLab) | Graylog fixes made after Q was forked in January 2025 |
| V | internal VictoriaLogs playbooks (GitLab) | VictoriaLogs roles, compose mode, Podman, TLS sources |
| M | internal monitoring installer (GitLab) | haproxy and keepalived exporters, uninstall flow, `docker` role |

Findings that shape the plan:

- Q's container tasks use `purge_networks`, which community.docker 4.x removed. Q pins 4.8.8, and CI only runs syntax
  checks, so this went unnoticed. nginx uses `openssl_certificate`, which community.crypto 2.0 removed.
- L is still where Graylog development happens. Q's 2025–2026 role fixes are ports of L changes, and several L fixes
  have not been ported yet.
- fluentbit, nginx, node_exporter, cadvisor, and proxy_exporter exist in three or four copies with different variable
  names. nginx configurations are stack-specific; only the container logic is shared.
- V duplicates every setting between its compose role and its per-component roles, and the copies have drifted
  (retention `"12"` vs `"30d"`, network `vm-network` vs `logging`). V's standalone `fluentbit` role is broken and
  unused.
- `proxy_exporter` is a proprietary internal tool. `prepare_manifest` and the ops-portal packaging belong to the
  internal delivery pipeline. Neither can ship publicly.

## Decisions

- **Home:** this public repository, plus a small internal overlay repository for internal-only content.
- **Packaging:** an Ansible collection. The overlay installs it by version through `requirements.yml`.
- **Graylog 4:** dropped. No `elasticsearch` role, no Elasticsearch exporter, no 4→5 or MongoDB 4→5 migration tasks.
- **VictoriaLogs modes:** both `containers` and `compose`, driven by one set of role defaults and templates.
- **VictoriaLogs topology:** `victorialogs_topology: single | ha | cluster`, independent of the deploy mode. In compose
  mode each host gets one compose file with only that host's components.
- **Compose:** one shared `compose_stack` role for every stack. Each component role provides a
  `tasks_from: compose_service` entry point; a stack is a list of component roles.
- **VictoriaMetrics:** `victoriametrics` and `vmagent` roles, with Molecule coverage but no playbook. `vmalert` and
  `vmauth` serve both VictoriaLogs and VictoriaMetrics.
- **Container runtime:** one shared `observability_container_runtime` switch. Podman is implemented and tested for the
  VictoriaLogs roles only; other roles are Docker-only until Podman is enabled for them.
- **Variables:** new role-prefixed names with deprecated aliases for old names, removed two minor releases later.
- **Testing:** Molecule scenarios for every role.
- **Delivery:** staged releases in this repository, in the order listed under [Stages](#stages).

## Target layout

```text
galaxy.yml
meta/runtime.yml
requirements.yml
extensions/molecule/          # shared Molecule config
playbooks/
  graylog.yml
  victorialogs.yml
  log_agents.yml
  exporters.yml
  playbook.yaml               # deprecated alias of graylog.yml, removed after one release
roles/
  host_prepare                # limits, users, NTP, sysctl, certificates
  container_runtime           # Docker daemon config, networks, run_container entry point
  artifact_fetch              # image and tarball download with registry, credentials, CA
  nginx                       # generic container; each stack passes its own config template
  keepalived                  # virtual IP for Graylog and VictoriaLogs HA
  compose_stack               # renders one compose file per host from a list of component roles
  mongodb
  opensearch
  graylog
  graylog_auth_proxy
  graylog_configuration
  graylog_output_duplicator
  victorialogs                # single node or cluster component: storage, insert, select
  vmalert                     # datasource set per stack: VictoriaLogs or VictoriaMetrics
  vmauth                      # routing and read load balancing for both stacks
  victoriametrics             # no playbook yet
  vmagent                     # no playbook yet
  fluentbit
  fluentd
  node_exporter
  cadvisor
  mongodb_exporter
  opensearch_exporter
  haproxy_exporter
  keepalived_exporter
docs/
  graylog.md
  victorialogs.md
  log-agents.md
  exporters.md
  victoriametrics.md          # preview: roles only
  variables.md
  migration.md
```

Each playbook targets one inventory group: `graylog`, `victorialogs`, `log_agents`, or `exporters`. A VictoriaLogs
cluster adds the child groups `victorialogs_storage`, `victorialogs_insert`, and `victorialogs_select`. Roles find their
peers through `groups[...]`, so peer addresses are not listed by hand.

## Shared conventions

- Every role variable starts with the role name. Keep ansible-lint's `var-naming[no-role-prefix]` enabled.
- Cross-role settings use the `observability_` prefix. A `vm`-based prefix is avoided because `vm` already means
  VictoriaMetrics in `vmalert`, `vmauth`, and `vmagent`.
  - `observability_container_runtime`: `docker` or `podman`.
  - `observability_image_registry`: replaces `docker_registry` and `vl_registry`.
  - `observability_artifacts_url`, `observability_artifacts_username`, `observability_artifacts_password`, and
    `observability_artifacts_ca_file`: replace `raw_artifacts_registry_*`.
  - `observability_data_dir` and `observability_config_dir`: replace `graylog_volume`, `global_data_dir`, and
    `exporters_config_path`.
  - `observability_tls_cert_source`: `selfsigned`, `content`, `local_file`, or `existing`.
  - `observability_container_network_mode`: `bridge` or `host`. HA and cluster setups need cross-host traffic.
  - `observability_advertise_address`: the address other hosts use to reach this one. Defaults to `ansible_host`.
  - `observability_vip` and `observability_vip_interface`: the virtual IP that the `keepalived` role manages.
- Topology settings stay per stack (`victorialogs_topology`), not global.
- Defaults point at public sources: Docker Hub, ghcr.io, and full GitHub release URLs. Setting
  `observability_image_registry` or `observability_artifacts_url` switches a role to a mirror.
- All modules use fully qualified names. Containers use `comparisons: {networks: strict}`.
- Deprecated aliases:
  - Each role lists old names in `vars/deprecated.yml`, with the source repository for each.
  - `defaults/main.yml` resolves each new name as `new: "{{ old | default(<default>) }}"`.
  - A `host_prepare` preflight task prints one warning that lists every old name set in the inventory.
  - `docs/migration.md` publishes the same tables.

## Stages

Each stage ends with a tagged release and updated docs.

### Stage 1: collection skeleton and runtime fixes

- [x] Add `galaxy.yml`, `meta/runtime.yml`, and a root `requirements.yml`; remove `tests/requirements.yml`.
- [x] Switch every module call to its fully qualified name.
- [x] Replace `purge_networks: true` with `comparisons: {networks: strict}` in all container tasks.
- [x] Replace `openssl_certificate` with `x509_certificate`. `openssl_privatekey` and `openssl_csr` still exist in
      community.crypto 3.x.
- [x] Fix the `graylog_output_duplicator/defaults/mailn.yaml` typo.
- [x] Fix the download URL logic in node_exporter, mongodb_exporter, opensearch_exporter, and cadvisor.
- [x] Add `playbooks/graylog.yml`; keep `playbooks/playbook.yaml` as a deprecated import of it.
- [x] Add a `graylog_stack` Molecule scenario on Ubuntu 24.04 (converge, verify `/api/system/lbstatus`, exporter
      metrics, and container state).
- [x] Add CI jobs: `ansible-test sanity`, ansible-lint with the `production` profile and a per-file baseline in
      `.ansible-lint-ignore`, and a Molecule matrix. A nightly schedule runs everything.
- [x] Add Renovate rules for image tags in role defaults. Major updates of Graylog, MongoDB, and OpenSearch stay manual.
- [x] Fix bugs that the first real deploy exposed: `daemon.json` failed without `docker_registry`, `docker_ports` had
      no default, grok patterns were created out of order, and pipeline rules broke on Windows line endings. The last
      two were stage 3 items.
- [ ] Release workflow: build the collection tarball on release and attach it to the GitHub release. It needs a
      decision on the tag and release flow (see the Qubership `tag-action` and `release-drafter` patterns).
- [ ] Renovate rules for GitHub release URLs in exporter defaults. The version appears twice in each URL, so a plain
      regex manager would break the file name.
- [ ] Idempotence in Molecule. Container tasks use `recreate: true`, so a second run always reports changes. Stage 2
      replaces this with restarts on config change in `container_runtime`.
- [ ] Rocky 9 platform for the scenario, and shared Molecule config once a second scenario exists.

### Stage 2: shared foundation

- [ ] Create `host_prepare` from V's `prepare-environment` structure. Add Q/L limits and users, plus NTP and DNS
      toggles.
- [ ] Create `container_runtime` from M's `docker` role. Merge the Docker tasks from Q, L, and V. Expose
      `tasks_from: run_container` and `tasks_from: network`.
- [ ] Create `artifact_fetch` with `tasks_from: binary`: a fresh staging directory per run, credentials, CA, and
      binary or tarball input.
- [ ] Introduce the `observability_*` variables, including the network and VIP settings, and the alias mechanism.
- [ ] Extract keepalived from `prepare_environment` into a shared `keepalived` role. Keep the Graylog health-check
      script as the Graylog stack's check.
- [ ] Move the remaining Graylog-only parts of `prepare_environment` (duplicator ports, container checks) into the
      `graylog` role, then remove `prepare_environment` and `common`.
- [ ] Add Molecule scenarios for the foundation roles and `keepalived`.

### Stage 3: Graylog fixes from L

- [ ] `graylog_configuration`: `is not none` guards, remove all content packs, boolean `tls_enable`, `lookup('file')`
      instead of nested templating. Grok pattern order and `\r` in rule sources were fixed in stage 1.
- [ ] `graylog_auth_proxy`: `domain`, `access_control_max_age`, cookie and session settings, and `technical_users_*`.
- [ ] `mongodb`: idempotent user creation without `ignore_errors`.
- [ ] `graylog`: `graylog_config_root_timezone`.
- [ ] Rename internal identifiers while porting (`NC_*` grok patterns to `QS_*`, `com.netcracker` to `org.qubership`).
- [ ] Leave the Bill Cycle content and internal plugins for the overlay.

### Stage 4: log agents and exporters

- [ ] `fluentbit`: base on L's tasks. Add `fluentbit_output: graylog | victorialogs | custom` with V's HTTP output and
      tuning variables. Make container name, network, links, and config directory variables. Fix `tls.key_passwd`,
      which is rendered as a file path. Add uninstall from M.
- [ ] `fluentd`: base on Q. Make the match tag a variable. Add uninstall from M.
- [ ] Exporters: one install flow over `artifact_fetch` with `*_install`, `*_uninstall`, and `*_keep_custom_config`.
- [ ] `cadvisor`: accept a binary or a tarball. Rename `cadvisor_runtime_optionts` and keep the old name as an alias.
      Update from v0.49.2: it uses Docker API 1.41, which Docker 29 rejects, so it collects no per-container metrics.
- [ ] Port `haproxy_exporter` and `keepalived_exporter` from M. Fix `raw_artifacts_registry_ca_cert_fil`.
- [ ] Add `playbooks/log_agents.yml` and `playbooks/exporters.yml`.
- [ ] Add Molecule scenarios that verify Fluent Bit on port 2020 and each exporter's `/metrics`.

### Stage 5: VictoriaLogs single node

- [ ] Port `victorialogs` (from `vlsingle`), `vmalert`, and `vmauth`. Each role owns its defaults and templates.
- [ ] Make `vmalert` and `vmauth` stack-neutral: datasource, remote-write target, and routes are settings.
- [ ] Create `compose_stack`. It takes `compose_stack_components` (a list of role names), calls each role's
      `tasks_from: compose_service`, and renders one `docker-compose.yml` per host. It defines no service settings of
      its own and owns the Docker and Podman compose handling.
- [ ] Add `tasks_from: compose_service` to `victorialogs`, `vmalert`, `vmauth`, `nginx`, and `fluentbit`.
- [ ] Add `victorialogs_deploy_mode: containers | compose` and `victorialogs_topology` with only `single` implemented.
- [ ] Unify defaults: retention `30d`, network `victorialogs`, the same host paths in both modes.
- [ ] Make TLS work in both modes through `host_prepare` certificates.
- [ ] Make the vmalert notifier URL optional.
- [ ] Reuse the `fluentbit` role templates for the compose-mode Fluent Bit container.
- [ ] Add `playbooks/victorialogs.yml`.
- [ ] Add Molecule scenarios `containers` and `compose` on Docker, and `containers` on rootful Podman (Rocky 9).
      Verify `/health`.

### Stage 6: internal overlay and cut-over

- [ ] Create the overlay repository with `requirements.yml` pinned to a collection release.
- [ ] Move `proxy_exporter` into the overlay. Replace the hardcoded module list with a `proxy_exporter_targets` list.
- [ ] Move `prepare_manifest` into the overlay. Base it on M's copy with V's `docker_repository_name` fix and a `{}`
      initializer for `tarball_artifacts_dict`. Make it set `observability_*` and image variables.
- [ ] Add the internal Graylog plugins, Bill Cycle content, and internal image defaults.
- [ ] Add wrapper playbooks that `import_playbook` the collection playbooks.
- [ ] Move the ops-portal packaging, delivery manifests, and GitLab CI into the overlay.
- [ ] Switch internal deployments to the overlay, then archive the internal logging installer and VictoriaLogs
      playbooks.
- [ ] Switch the monitoring installer to the collection's exporter roles. Its server roles stay where they are.

### Stage 7: VictoriaLogs HA and cluster

Check the topology details below against the VictoriaLogs documentation for the pinned version before implementing.

- [ ] `ha`: two or more independent single-node instances. Agents write every record to all instances, through
      Fluent Bit's multiple outputs or `vlagent`. `vmauth` balances reads, and `keepalived` holds one virtual IP.
- [ ] `cluster`: `victorialogs_cluster_role: storage | insert | select`, taken from the host's inventory group. Insert
      and select nodes get the storage node list from `groups['victorialogs_storage']`.
- [ ] HA over a cluster: two clusters with agents writing to both. Document this as a pattern; no extra role.
- [ ] `fluentbit`: accept a list of VictoriaLogs targets for the `victorialogs` output.
- [ ] Support both deploy modes for every topology. In compose mode each host's file holds that host's components.
- [ ] Add example inventories for `ha` and `cluster` in `docs/victorialogs.md`.
- [ ] Add multi-instance Molecule scenarios: `ha` (2 nodes) and `cluster` (2 storage, 1 insert, 1 select). Run them
      nightly and on tags only.

### Stage 8: VictoriaMetrics roles without a playbook

- [ ] Port `victoriametrics` from M's `vmetrics`: single node, retention, data directory, flags.
- [ ] Port `vmagent` from M. Make remote-write targets and scrape configs settings; M hardcodes them to its server.
- [ ] Add `tasks_from: compose_service` to both roles, so `compose_stack` can deploy
      `[victoriametrics, vmagent, vmalert, vmauth]`.
- [ ] Add a Molecule scenario in compose mode that verifies `/health` and a vmagent scrape. It guards the roles while no
      playbook uses them.
- [ ] Document the roles in `docs/victoriametrics.md` as preview, with an example play.

## Out of scope

- Grafana, Alertmanager, Postgres, the backup daemon, and other monitoring server roles from M.
- VictoriaMetrics cluster and a VictoriaMetrics playbook.
- Built-in replication between VictoriaLogs storage nodes; HA relies on independent instances or clusters.
- Podman for the Graylog stack, agents, and exporters.
- Publishing to Ansible Galaxy. The GitHub release tarball is enough for the overlay.

## Risks

- Rewriting the history of the internal repositories is not planned. Port code as new commits so that Jira keys and
  customer names stay internal.
- The OpenSearch demo certificates in `roles/opensearch/files/default-config/` ship in both Q and L. Decide in stage 1
  whether to keep them as documented test-only defaults or generate them at install time.
- Molecule with systemd and the host Docker socket is slow. Limit PR runs to roles a change touches.
- Every component role must implement the `compose_service` contract. Document it in `roles/compose_stack/README.md`
  and test it in each role's compose scenario, or the contract drifts like V's compose and individual roles did.
- Roles without a playbook tend to rot. The stage 8 Molecule scenario is the only guard, so keep it in the nightly run.
