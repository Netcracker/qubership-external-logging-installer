---
paths:
  - "**/*"
---

# Repository Workflow

When changing or reviewing this repository:

- Treat `docs/installation.md` as the main installation reference and keep it aligned with `playbooks/`, `roles/`,
  defaults, templates, and inventory examples.
- Before choosing checks, inspect `.github/workflows/`, `.github/linters/`, `.github/super-linter.env`, and
  `.pre-commit-config.yaml`.
- For Ansible syntax checks from this checkout, use
  `ANSIBLE_ROLES_PATH=roles ansible-playbook --syntax-check playbooks/playbook.yaml`.
- For Markdown edits, apply `markdown-line-length-120` and use `.github/linters/.markdownlint.yaml`.
- For APM changes, edit `apm.yml`, run `apm install`, and do not hand-edit dependency-generated rules or skills.
