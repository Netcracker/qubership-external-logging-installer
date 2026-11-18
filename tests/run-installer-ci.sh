#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"

export ANSIBLE_ROLES_PATH="${root}/roles"
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible}"
export ANSIBLE_COLLECTIONS_PATH="${ANSIBLE_COLLECTIONS_PATH:-${root}/.ansible/collections}"
export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-false}"

inventory="${root}/tests/fixtures/inventory.ci.yml"
playbook="${root}/playbooks/graylog.yml"
legacy_playbook="${root}/playbooks/playbook.yaml"
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
    if ansible-galaxy collection install -r "${root}/requirements.yml" -p "${ANSIBLE_COLLECTIONS_PATH}"; then
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

echo "==> Syntax-check playbooks against the CI inventory"
ansible-playbook --syntax-check -i "${inventory}" "${playbook}"
ansible-playbook --syntax-check -i "${inventory}" "${legacy_playbook}"

echo "==> Build and install the collection"
build_dir="$(mktemp -d)"
trap 'rm -rf "${build_dir}"' EXIT
ansible-galaxy collection build --force --output-path "${build_dir}" "${root}"
# Install into a separate path, so later checks keep resolving roles from this checkout.
ansible-galaxy collection install --force --no-deps -p "${build_dir}/collections" \
    "${build_dir}"/qubership-observability-*.tar.gz

echo "==> Syntax-check the installed collection playbook"
(cd "${build_dir}" && ANSIBLE_ROLES_PATH="${build_dir}/no-roles" \
    ANSIBLE_COLLECTIONS_PATH="${build_dir}/collections:${ANSIBLE_COLLECTIONS_PATH}" \
    ansible-playbook --syntax-check -i "${inventory}" qubership.observability.graylog)

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

echo "==> Test how the graylog role keeps an existing password secret"
ansible-playbook -i localhost, "${root}/tests/graylog_password_secret/test.yml"

echo "==> Check that --diff does not print the Graylog password secret"
diff_volume="${build_dir}/graylog-volume"
diff_secret="DiffCheckSecretThatMustNotAppearInTheOutput$(date +%s%N)"
mkdir -p "${diff_volume}/graylog/config"
printf 'password_secret = %s\nis_leader = true\n' "${diff_secret}" >"${diff_volume}/graylog/config/graylog.conf"
diff_output="$(ansible-playbook -i localhost, --check --diff "${root}/tests/graylog_password_secret/diff.yml" \
    -e "graylog_volume=${diff_volume}" -e "graylog_uid=$(id -u)" -e "graylog_gid=$(id -g)")"
if grep -qF -- "${diff_secret}" <<<"${diff_output}"; then
    echo "::error::ansible-playbook --diff printed the Graylog password secret"
    exit 1
fi
# The log4j2.xml diff proves that the run printed diffs at all.
if ! grep -qF -- "log4j2.xml" <<<"${diff_output}"; then
    printf '%s\n' "${diff_output}"
    echo "::error::ansible-playbook --diff printed no diff, so the secret check proves nothing"
    exit 1
fi

echo "==> ansible-lint (production profile, baseline in .ansible-lint-ignore)"
ansible-lint
