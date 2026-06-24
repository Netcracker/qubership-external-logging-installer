# AGENTS.md

This repository contains an Ansible installer for a VM-based logging stack built around Graylog, OpenSearch,
MongoDB, Fluent Bit, Fluentd, Nginx, Keepalived, and Prometheus exporters.

## Repository map

- `playbooks/playbook.yaml` is the main installation entry point.
- `roles/*` contains the Ansible roles for logging, storage, proxying, monitoring, and supporting services.
- `ansible.cfg` points `roles_path` to `/ansible/roles` for containerized or CI execution. For local checks from this
  checkout, override it with `ANSIBLE_ROLES_PATH=roles`.
- `docs/installation.md` is the primary installation reference; keep it aligned with playbooks, roles, and defaults.
- `docs/mongodb_authentication.md`, `docs/observability.md`, and `docs/password-change-guide.md` cover operational
  procedures that can drift when role variables or templates change.
- `.github/workflows/`, `.github/linters/`, `.github/super-linter.env`, and `.pre-commit-config.yaml` define the checks
  that PRs run.

## Working rules

- Prefer small, evidence-based changes. Inspect the role, defaults, templates, handlers, and related docs before
  editing.
- For Markdown changes, wrap body text at 120 characters and use named links instead of bare URLs.
- For APM dependency changes, edit `apm.yml`, then run `apm install` for this repository.
- Do not edit dependency-generated skills or rules directly unless the user explicitly asks for a temporary local patch.
  Change the upstream package instead, then update `apm.yml` or the lockfile.

## Verification

- Run the narrowest relevant Ansible, lint, or documentation checks for the files you changed.
- For playbook syntax checks from the repository root, use `ANSIBLE_ROLES_PATH=roles ansible-playbook --syntax-check
  playbooks/playbook.yaml`. In a sandbox with a read-only home directory, also set `ANSIBLE_LOCAL_TEMP=/tmp/ansible`.
- For APM changes, run `apm audit --ci --no-policy` after `apm install`.
- For Markdown or docs-only changes, run markdownlint with `.github/linters/.markdownlint.yaml` on the changed files
  when the tool is available.
- Before patching CI failures, inspect the workflow logs and reproduce the failing check locally where practical.

## Review checklist

- Check that docs stay in sync with changed role variables, templates, playbooks, inventory examples, and default
  values.
- Check that linter exclusions only cover generated dependency assets, not source files under `.apm/`, `docs/`,
  `roles/`, or `playbooks/`.
- Check that secrets, credentials, inventory hostnames, and environment-specific values are not committed.
