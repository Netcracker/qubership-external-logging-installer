#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"

export ANSIBLE_ROLES_PATH="${root}/roles"
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible}"
export ANSIBLE_COLLECTIONS_PATH="${ANSIBLE_COLLECTIONS_PATH:-${root}/.ansible/collections}"
export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-false}"

inventory="${root}/tests/fixtures/inventory.ci.yml"
playbook="${root}/playbooks/playbook.yaml"
expected_roles=(
  common
  prepare_environment
  mongodb
  opensearch
  graylog_auth_proxy
  graylog
  nginx
  graylog_configuration
  graylog_output_duplicator
  fluentd
  fluentbit
  node_exporter
  mongodb_exporter
  opensearch_exporter
  cadvisor
)

mkdir -p "${ANSIBLE_LOCAL_TEMP}" "${ANSIBLE_COLLECTIONS_PATH}"

echo "==> Install Ansible collections"
galaxy_ok=0
for attempt in 1 2 3 4 5; do
  if ansible-galaxy collection install -r "${root}/tests/requirements.yml" -p "${ANSIBLE_COLLECTIONS_PATH}"; then
    galaxy_ok=1
    break
  fi
  echo "ansible-galaxy failed (attempt ${attempt}/5); retrying"
  sleep $((attempt * 3))
done
if [[ "${galaxy_ok}" -ne 1 ]]; then
  echo "::error::ansible-galaxy collection install failed after retries"
  exit 1
fi

echo "==> Syntax-check playbook against the CI inventory"
ansible-playbook --syntax-check -i "${inventory}" "${playbook}"

echo "==> Parse CI inventory"
ansible-inventory -i "${inventory}" --list >/dev/null

echo "==> List tasks from the install playbook"
ansible-playbook -i "${inventory}" "${playbook}" --list-tasks

echo "==> Syntax-check each role"
for role in "${expected_roles[@]}"; do
  echo "-- ${role}"
  ansible-playbook --syntax-check -i "${inventory}" \
    "${root}/tests/fixtures/role-syntax.yml" \
    -e "ci_role=${role}"
done

echo "==> ansible-lint (min profile)"
ansible-lint "${playbook}"
