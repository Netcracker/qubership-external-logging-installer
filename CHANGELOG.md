# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- The repository is an Ansible collection, `qubership.observability`. Install it with `ansible-galaxy collection
  install` and run `qubership.observability.graylog`.
- `playbooks/graylog.yml` deploys the Graylog stack on the `graylog` inventory group. Set `graylog_target_hosts` to
  target another group.
- A Molecule scenario, `graylog_stack`, deploys the playbook into a container and checks Graylog, the exporters, and
  the stack containers.
- `graylog_password_secret` sets the Graylog `password_secret`.

### Changed

- Every module call uses its fully qualified name.
- The collection requirements file moved from `tests/requirements.yml` to `requirements.yml`.
- ansible-lint runs the `production` profile on the whole collection. Existing violations are listed in
  `.ansible-lint-ignore`.
- graylog_configuration and graylog_output_duplicator build lookup paths with Jinja expressions instead of templates
  nested in strings, which ansible-core 2.23 stops rendering.

### Deprecated

- `playbooks/playbook.yaml`. It still runs `graylog.yml` on all hosts and prints a warning. Use `playbooks/graylog.yml`.

### Fixed

- Container tasks failed with community.docker 4.x because `purge_networks` was removed. They now use
  `comparisons: {networks: strict}`.
- The nginx self-signed certificate task failed with community.crypto 2.0 and later because `openssl_certificate` was
  removed. It now uses `x509_certificate`.
- node_exporter, mongodb_exporter, opensearch_exporter, and cadvisor no longer prefix a full download URL with
  `raw_artifacts_registry`, and no longer fail when `raw_artifacts_registry` is not set.
- `graylog_output_duplicator` now loads its defaults. The file was named `defaults/mailn.yaml`. With the defaults
  loaded, the role turns on when `other_side_graylog_host` is set. It now loads the request templates and processing
  rules that it shares with `graylog_configuration` from that role, instead of looking for them in its own files.
- Preflight checks failed when the inventory did not set `graylog_heap_size_mb` or `elasticsearch_heap_size_mb`. They
  now use the 2048 MiB default of the graylog and opensearch roles.
- `--check` runs failed in preflight, because check mode skipped the read-only disk, RAM, CPU, and Docker commands.
  These commands now run in check mode too.
- Exporter download URLs built from a `raw_artifacts_registry` without a scheme had no scheme either, so `get_url`
  rejected them. They now get `https://`, as the registry origin check already assumed.
- The MongoDB restart task no longer sets `recreate` twice.
- The Docker `daemon.json` template failed when `docker_registry` was not set, although the parameter is optional. The
  insecure registry entry is now written only when `docker_registry` is set.
- `docker_ports` had no default, so Graylog failed to deploy unless the inventory set it. It now defaults to `[12201]`.
- Grok patterns are created in the order of `grok_patterns.json`. A fresh install failed because `QS_MFBACKEND` was
  created before `QS_MILLISECS`, which it references.
- Pipeline rules failed to install from a checkout with Windows line endings, because Graylog rejects carriage returns
  in the rule source. They are now removed before the rule is sent.
- Role shell scripts start with `#!/usr/bin/env bash`, which `ansible-test sanity` accepts.
- With ansible-core 2.19 and later, a fresh install failed or misbehaved in graylog_configuration:
  - the GELF TCP input request sent `"tls_enable": False`, which is not JSON
  - content pack, dashboard, and extractor lookups that found nothing broke the next condition
  - a broken condition hid the warning about an unsupported OS
- The Operator and Audit Viewer role requests were invalid JSON when the "Other site logs" stream existed.

### Security

- `graylog.conf` no longer ships one hardcoded `password_secret` for every installation. `graylog_password_secret`
  sets the secret. Without it, the role keeps the secret from `graylog_custom_params.password_secret` or from the
  existing `graylog.conf`, so users stay signed in and encrypted values stay readable, and it warns when that secret is
  the old public one. Only a fresh install with the bundled MongoDB gets a random 96-character secret. The role stops
  and asks for `graylog_password_secret` when `graylog.conf` is missing and Graylog uses a custom MongoDB or the
  bundled one already has Graylog collections. See the password secret rules in `docs/installation.md`.
- The exporter roles send the raw registry credentials and TLS settings only to URLs on the scheme, host, and port of
  `raw_artifacts_registry`. They used to send them with every download. An inventory that downloads from a mirror on
  another origin with `raw_artifacts_registry_ca_cert_file` must now set `raw_artifacts_registry` to that mirror, or
  add the mirror CA to the trust store of the target hosts.
