# troubleshoot-external-logging

A single user-invoked skill that diagnoses problems with the Qubership External Logging Installer (an Ansible installer
for a Graylog + OpenSearch + MongoDB logging stack on virtual machines).

The skill is **read-only and advisory**. It does not run `kubectl`, SSH, or Ansible, and it never changes a system. It
reads a pasted problem description plus any attached logs or configuration, matches the symptom against a curated
reference, and returns a diagnosis with remediation steps and a list of data to collect when the match is uncertain.

## Contents

| Path | Purpose |
| ---- | ------- |
| [`SKILL.md`](.apm/skills/troubleshoot-external-logging/SKILL.md) | The diagnosis procedure. |
| [`references/troubleshooting.md`](.apm/skills/troubleshoot-external-logging/references/troubleshooting.md) | Symptom-indexed failure catalog, compiled from external sources. |
| [`scripts/show_cases.py`](.apm/skills/troubleshoot-external-logging/scripts/show_cases.py) | Symptom-catalog and section reader. |

The reference is also exposed at `docs/troubleshooting/troubleshooting.md` in the repository root via a symlink.
