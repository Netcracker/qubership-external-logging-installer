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

### Changed

- Every module call uses its fully qualified name.
- The collection requirements file moved from `tests/requirements.yml` to `requirements.yml`.
- ansible-lint runs the `production` profile on the whole collection. Existing violations are listed in
  `.ansible-lint-ignore`.

### Deprecated

- `playbooks/playbook.yaml`. It still runs `graylog.yml` on all hosts and prints a warning. Use `playbooks/graylog.yml`.

### Fixed

- Container tasks failed with community.docker 4.x because `purge_networks` was removed. They now use
  `comparisons: {networks: strict}`.
- The nginx self-signed certificate task failed with community.crypto 2.0 and later because `openssl_certificate` was
  removed. It now uses `x509_certificate`.
- node_exporter, mongodb_exporter, opensearch_exporter, and cadvisor no longer prefix a full download URL with
  `raw_artifacts_registry`, and no longer fail when `raw_artifacts_registry` is not set.
- `graylog_output_duplicator` now loads its defaults. The file was named `defaults/mailn.yaml`.
- The MongoDB restart task no longer sets `recreate` twice.
- The Docker `daemon.json` template failed when `docker_registry` was not set, although the parameter is optional. The
  insecure registry entry is now written only when `docker_registry` is set.
- `docker_ports` had no default, so Graylog failed to deploy unless the inventory set it. It now defaults to `[12201]`.
- Grok patterns are created in the order of `grok_patterns.json`. A fresh install failed because `QS_MFBACKEND` was
  created before `QS_MILLISECS`, which it references.
- Pipeline rules failed to install from a checkout with Windows line endings, because Graylog rejects carriage returns
  in the rule source. They are now removed before the rule is sent.
- Role shell scripts start with `#!/usr/bin/env bash`, which `ansible-test sanity` accepts.
