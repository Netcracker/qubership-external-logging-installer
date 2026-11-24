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
# Build from the tracked files only, as the README recommends, so untracked files in the checkout never reach the
# archive. The copy takes the working-tree content of each tracked file, so local edits to tracked files are tested.
copy_tracked_source() {
    mkdir -p "$1"
    git -C "${root}" ls-files -z | (cd "${root}" && tar --null --ignore-failed-read -T - -cf -) | tar -x -C "$1"
}
copy_tracked_source "${build_dir}/src"
ansible-galaxy collection build --force --output-path "${build_dir}" "${build_dir}/src"

echo "==> Check that build_ignore keeps local inventories out of an in-place build"
# Plant inventory files in a second copy, never in the checkout, so a run cannot overwrite or remove local files.
leak_src="${build_dir}/leak-src"
leak_marker="InventoryLeakMarker$(date +%s%N)"
copy_tracked_source "${leak_src}"
mkdir -p "${leak_src}/inventory" "${leak_src}/group_vars" "${leak_src}/host_vars"
for leak_file in inventory.yml inventory-prod.ini inventory/hosts.yaml group_vars/all.yml host_vars/host1.yml; do
    printf 'all:\n  vars:\n    root_password: %s\n' "${leak_marker}" >"${leak_src}/${leak_file}"
done
ansible-galaxy collection build --force --output-path "${build_dir}/leak-out" "${leak_src}" >/dev/null
mkdir -p "${build_dir}/leak-files"
if ! tar -xzf "${build_dir}"/leak-out/qubership-observability-*.tar.gz -C "${build_dir}/leak-files"; then
    echo "::error::Cannot read the collection archive built with planted inventory files"
    exit 1
fi
leaked="$(cd "${build_dir}/leak-files" && {
    find . \( -name 'inventory*' -o -name group_vars -o -name host_vars \) -print
    grep -rlF -- "${leak_marker}" . || true
})"
if [[ -n "${leaked}" ]]; then
    echo "::error::The collection archive contains planted inventory files:"
    printf '%s\n' "${leaked}"
    exit 1
fi

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

echo "==> Compare the java_properties module with java.util.Properties"
if command -v java >/dev/null 2>&1; then
    python3 "${root}/tests/java_properties/differential.py" "${build_dir}/java-properties"
elif [[ "${CI:-}" == "true" ]]; then
    echo "::error::java is not on PATH, so the java_properties module cannot be compared with Java"
    exit 1
else
    echo "java is not on PATH; skipping the comparison with Java"
fi

echo "==> Test the origin check for raw artifact downloads"
ansible-playbook -i localhost, "${root}/tests/raw_artifacts_origin/test.yml"

echo "==> Test the processing rule request renderer"
ansible-playbook -i localhost, "${root}/tests/graylog_processing_rule/test.yml"

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

echo "==> Write graylog.conf with the installed collection"
# Collection roles load no plugins from their own directories, so this proves that the role finds java_properties.
installed_volume="${build_dir}/installed-volume"
installed_secret="InstalledCollectionSecret$(date +%s%N)"
mkdir -p "${installed_volume}/graylog/config"
printf 'password_secret = %s\n' "${installed_secret}" >"${installed_volume}/graylog/config/graylog.conf"
(cd "${build_dir}" && ANSIBLE_ROLES_PATH="${build_dir}/no-roles" \
    ANSIBLE_COLLECTIONS_PATH="${build_dir}/collections:${ANSIBLE_COLLECTIONS_PATH}" \
    ansible-playbook -i localhost, "${root}/tests/graylog_password_secret/diff.yml" \
    -e graylog_role=qubership.observability.graylog -e "graylog_volume=${installed_volume}" \
    -e "graylog_uid=$(id -u)" -e "graylog_gid=$(id -g)" >/dev/null)
if ! grep -qxF -- "password_secret = ${installed_secret}" "${installed_volume}/graylog/config/graylog.conf"; then
    echo "::error::The installed collection did not keep the existing password secret in graylog.conf"
    exit 1
fi

echo "==> ansible-lint (production profile, baseline in .ansible-lint-ignore)"
ansible-lint
