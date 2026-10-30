#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

config_file=$(node_naming_config_file_path)
[[ "${config_file}" == "${SB_PROJECT_DIR}/node-naming.json" ]]
[[ "$(node_name_host_label)" == test-host ]]
[[ ! -e "${config_file}" ]]

# This setting must remain a local display preference; an accidental call to
# sync, networking or service control makes the test fail immediately.
curl() { printf 'unexpected network access from naming settings\n' >&2; return 99; }
systemctl() { printf 'unexpected service operation from naming settings\n' >&2; return 99; }
push_subman_node() { printf 'unexpected SubMan write from naming settings\n' >&2; return 99; }
SUBMAN_NODE_PREFIX=unchanged-identity
original_key=$(subman_external_key_for_hy2_user main alice IPv4)
max_label=$(printf '%128s' '' | tr ' ' a)
write_node_naming_config "${max_label}"
[[ "$(node_name_host_label)" == "${max_label}" ]]
rm "${config_file}"
write_node_naming_config '  fra-01  '
[[ "$(stat -c %a "${config_file}")" == 600 ]]
jq -e 'keys == ["host_label"] and .host_label == "fra-01"' "${config_file}" >/dev/null
[[ "$(node_name_host_label)" == fra-01 ]]
[[ "$(default_instance_node_name hy2)" == fra-01-hy2-01 ]]
[[ "$(subman_external_key_for_hy2_user main alice IPv4)" == "${original_key}" ]]
cp "${config_file}" "${TMP_DIR}/first.json"
write_node_naming_config '德国一号'
cmp "${TMP_DIR}/first.json" "${config_file}.bak"
[[ "$(stat -c %a "${config_file}.bak")" == 600 ]]
[[ "$(node_name_host_label)" == 德国一号 ]]
[[ "$(subman_external_key_for_hy2_user main alice IPv4)" == "${original_key}" ]]
cp "${config_file}" "${TMP_DIR}/current.json"
cp "${config_file}.bak" "${TMP_DIR}/backup.json"

for invalid_label in '' '   ' $'bad\nlabel' $'bad\tlabel' $'bad\177label' "$(printf '%129s' '' | tr ' ' a)" "$(jq -nr '"德" * 43')"; do
  if write_node_naming_config "${invalid_label}" >"${TMP_DIR}/invalid.out" 2>"${TMP_DIR}/invalid.err"; then
    printf 'invalid naming label unexpectedly accepted\n' >&2
    exit 1
  fi
  cmp "${TMP_DIR}/current.json" "${config_file}"
  cmp "${TMP_DIR}/backup.json" "${config_file}.bak"
done

# Reading an existing malformed or unknown-format preference must not silently
# substitute another display label and unexpectedly rename future instances.
for invalid_document in 'not-json' '{}' '{"host_label":""}' '{"host_label":"ok","unknown":true}' '{"host_label":1}' '{"host_label":" not-trimmed "}' '{"host_label":"bad\nlabel"}' '{"host_label":"bad\u0000label"}'; do
  printf '%s\n' "${invalid_document}" > "${config_file}"
  if node_name_host_label >"${TMP_DIR}/read-invalid.out" 2>"${TMP_DIR}/read-invalid.err"; then
    printf 'invalid naming document unexpectedly accepted\n' >&2
    exit 1
  fi
done
if default_instance_node_name hy2 >"${TMP_DIR}/invalid-default.out" 2>"${TMP_DIR}/invalid-default.err"; then
  printf 'invalid saved label unexpectedly produced a default name\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/invalid-default.out" ]]
grep -Fq 'node-naming.json' "${TMP_DIR}/invalid-default.err"
cp "${TMP_DIR}/current.json" "${config_file}"

# Blank input retains the exact saved preference. EOF is cancellation and must
# not save an incomplete setting or rotate its backup.
configure_node_naming_interactive >"${TMP_DIR}/blank.out" 2>"${TMP_DIR}/blank.err" <<'INPUT'

INPUT
cmp "${TMP_DIR}/current.json" "${config_file}"
cp "${config_file}.bak" "${TMP_DIR}/before-eof-backup.json"
if configure_node_naming_interactive </dev/null >"${TMP_DIR}/eof.out" 2>"${TMP_DIR}/eof.err"; then
  printf 'EOF must cancel naming preference changes\n' >&2
  exit 1
fi
cmp "${TMP_DIR}/current.json" "${config_file}"
cmp "${TMP_DIR}/before-eof-backup.json" "${config_file}.bak"
configure_node_naming_interactive >"${TMP_DIR}/edit.out" 2>"${TMP_DIR}/edit.err" <<'INPUT'
new-label
INPUT
[[ "$(node_name_host_label)" == new-label ]]
cmp "${TMP_DIR}/current.json" "${config_file}.bak"
[[ "$(subman_external_key_for_hy2_user main alice IPv4)" == "${original_key}" ]]
cp "${config_file}" "${TMP_DIR}/before-failure.json"

# Inject a failure at atomic publication. The previous preference and external
# target remain untouched; temporary staging files must be cleaned afterwards.
mv() {
  local arguments=("$@") destination
  destination=${arguments[${#arguments[@]}-1]}
  if [[ "${destination}" == "${config_file}" ]]; then return 74; fi
  command mv "$@"
}
if write_node_naming_config failed-commit >"${TMP_DIR}/commit.out" 2>"${TMP_DIR}/commit.err"; then
  printf 'failed atomic publish was reported as success\n' >&2
  exit 1
fi
unset -f mv
cmp "${TMP_DIR}/before-failure.json" "${config_file}"
leftovers=$(find "${SB_PROJECT_DIR}" -maxdepth 1 -type f -name '.node-naming.*' -print)
[[ -z "${leftovers}" ]]

printf '%s\n' 'outside target must stay unchanged' > "${TMP_DIR}/outside"
cp "${TMP_DIR}/outside" "${TMP_DIR}/outside.expected"
rm "${config_file}"
ln -s "${TMP_DIR}/outside" "${config_file}"
if write_node_naming_config symlink-target >"${TMP_DIR}/symlink.out" 2>"${TMP_DIR}/symlink.err"; then
  printf 'symlink naming target unexpectedly accepted\n' >&2
  exit 1
fi
[[ -L "${config_file}" ]]
cmp "${TMP_DIR}/outside.expected" "${TMP_DIR}/outside"
if node_name_host_label >"${TMP_DIR}/symlink-read.out" 2>"${TMP_DIR}/symlink-read.err"; then
  printf 'symlink naming source unexpectedly accepted\n' >&2
  exit 1
fi
rm "${config_file}"
cp "${TMP_DIR}/before-failure.json" "${config_file}"
rm "${config_file}.bak"
ln -s "${TMP_DIR}/outside" "${config_file}.bak"
if write_node_naming_config symlink-backup >"${TMP_DIR}/backup-link.out" 2>"${TMP_DIR}/backup-link.err"; then
  printf 'symlink naming backup unexpectedly accepted\n' >&2
  exit 1
fi
cmp "${TMP_DIR}/before-failure.json" "${config_file}"
cmp "${TMP_DIR}/outside.expected" "${TMP_DIR}/outside"

# A directory at the backup path must not receive a copied file or have its
# permissions changed by the private-file chmod step.
rm "${config_file}.bak"
mkdir -m 700 "${config_file}.bak"
if write_node_naming_config directory-backup >"${TMP_DIR}/backup-dir.out" 2>"${TMP_DIR}/backup-dir.err"; then
  printf 'directory naming backup unexpectedly accepted\n' >&2
  exit 1
fi
[[ "$(stat -c %a "${config_file}.bak")" == 700 ]]
[[ -z "$(find "${config_file}.bak" -mindepth 1 -print -quit)" ]]
cmp "${TMP_DIR}/before-failure.json" "${config_file}"

printf 'Node naming settings passed: display-only identity, private backup, rejected input, EOF, atomic failure and symlink preservation\n'
