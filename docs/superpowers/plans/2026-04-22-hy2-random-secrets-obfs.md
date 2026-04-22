# HY2 Random Secrets And Optional OBFS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `hy2` use strong auto-generated secrets by default while keeping `obfs` disabled unless the user explicitly enables it.

**Architecture:** Keep `install.sh` as the single runtime source of truth. Add small secret-generation helpers, update the `hy2` install/update prompts to support auto-generated or manual secrets, and cover the behavior with focused shell regression tests plus the existing remote verification workflow.

**Tech Stack:** Bash, jq, OpenSSL, existing shell-based tests, remote verification via `dev/verification/run.sh`

---

### Task 1: Add Failing Tests For HY2 Secret Defaults

**Files:**
- Create: `tests/hy2_install_auto_generates_password_when_blank.sh`
- Create: `tests/hy2_install_auto_generates_obfs_password_when_enabled.sh`
- Create: `tests/hy2_update_preserves_manual_passwords.sh`
- Test: `install.sh`

- [ ] **Step 1: Write the failing test for auto-generated HY2 password**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cp "${REPO_ROOT}/install.sh" "${TMP_DIR}/install.sh"

cat <<'EOF' > "${TMP_DIR}/harness.sh"
#!/usr/bin/env bash
set -euo pipefail
source ./install.sh

ensure_hy2_materials() { :; }
get_public_ip() { printf '198.51.100.10'; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
open_all_protocol_ports() { :; }
setup_service() { :; }
generate_config() { :; }
check_config_valid() { :; }
save_current_state() { :; }
save_protocol_state_for_current_selection() { save_hy2_state; }
save_hy2_state() {
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<STATE
PASSWORD=${SB_HY2_PASSWORD}
STATE
}

export SB_PROTOCOL_STATE_DIR="${PWD}/protocols"
export SB_PROJECT_DIR="${PWD}/project"
mkdir -p "${SB_PROJECT_DIR}" "${SB_PROTOCOL_STATE_DIR}"
set_protocol_defaults "hy2"

prompt_hy2_install <<'INPUT'
hy2.example.com




n
manual
/etc/ssl/certs/hy2.pem
/etc/ssl/private/hy2.key

INPUT

printf 'PASSWORD=%s\n' "${SB_HY2_PASSWORD}"
EOF

chmod +x "${TMP_DIR}/harness.sh"
```

- [ ] **Step 2: Run test to verify it fails before the implementation**

Run: `bash tests/hy2_install_auto_generates_password_when_blank.sh`
Expected: FAIL because the generated output still contains an empty or weak default password assertion target.

- [ ] **Step 3: Write the test assertions**

```bash
output=$(cd "${TMP_DIR}" && bash ./harness.sh)
password=${output#PASSWORD=}

if [[ -z "${password}" ]]; then
  printf 'expected hy2 install to auto-generate a password when blank\n' >&2
  exit 1
fi

if [[ "${password}" == "hy2-password" ]]; then
  printf 'expected hy2 install to avoid weak placeholder password, got %s\n' "${password}" >&2
  exit 1
fi

if [[ ${#password} -lt 24 ]]; then
  printf 'expected generated hy2 password to be at least 24 chars, got %s\n' "${password}" >&2
  exit 1
fi
```

- [ ] **Step 4: Write the failing test for auto-generated OBFS password**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cp "${REPO_ROOT}/install.sh" "${TMP_DIR}/install.sh"

cat <<'EOF' > "${TMP_DIR}/harness.sh"
#!/usr/bin/env bash
set -euo pipefail
source ./install.sh

ensure_hy2_materials() { :; }
set_protocol_defaults "hy2"

prompt_hy2_install <<'INPUT'
hy2.example.com




y

manual
/etc/ssl/certs/hy2.pem
/etc/ssl/private/hy2.key

INPUT

printf 'OBFS_ENABLED=%s\n' "${SB_HY2_OBFS_ENABLED}"
printf 'OBFS_TYPE=%s\n' "${SB_HY2_OBFS_TYPE}"
printf 'OBFS_PASSWORD=%s\n' "${SB_HY2_OBFS_PASSWORD}"
EOF

chmod +x "${TMP_DIR}/harness.sh"
```

- [ ] **Step 5: Run test to verify it fails before the implementation**

Run: `bash tests/hy2_install_auto_generates_obfs_password_when_enabled.sh`
Expected: FAIL because `SB_HY2_OBFS_PASSWORD` remains blank when OBFS is enabled with empty input.

- [ ] **Step 6: Write the test assertions**

```bash
output=$(cd "${TMP_DIR}" && bash ./harness.sh)

if [[ "${output}" != *"OBFS_ENABLED=y"* ]]; then
  printf 'expected obfs to be enabled in hy2 install output, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"OBFS_TYPE=salamander"* ]]; then
  printf 'expected hy2 obfs type to default to salamander, got:\n%s\n' "${output}" >&2
  exit 1
fi

obfs_password=$(printf '%s\n' "${output}" | sed -n 's/^OBFS_PASSWORD=//p')
if [[ -z "${obfs_password}" ]]; then
  printf 'expected hy2 install to auto-generate obfs password when enabled\n' >&2
  exit 1
fi

if [[ ${#obfs_password} -lt 24 ]]; then
  printf 'expected generated obfs password to be at least 24 chars, got %s\n' "${obfs_password}" >&2
  exit 1
fi
```

- [ ] **Step 7: Write the failing test for preserving manual passwords on update**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cp "${REPO_ROOT}/install.sh" "${TMP_DIR}/install.sh"

cat <<'EOF' > "${TMP_DIR}/harness.sh"
#!/usr/bin/env bash
set -euo pipefail
source ./install.sh

set_protocol_defaults "hy2"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_PASSWORD="manual-hy2-password"
SB_HY2_OBFS_ENABLED="y"
SB_HY2_OBFS_TYPE="salamander"
SB_HY2_OBFS_PASSWORD="manual-obfs-password"
SB_HY2_TLS_MODE="manual"
SB_HY2_CERT_PATH="/etc/ssl/certs/hy2.pem"
SB_HY2_KEY_PATH="/etc/ssl/private/hy2.key"

prompt_hy2_update <<'INPUT'







INPUT

printf 'PASSWORD=%s\n' "${SB_HY2_PASSWORD}"
printf 'OBFS_PASSWORD=%s\n' "${SB_HY2_OBFS_PASSWORD}"
EOF

chmod +x "${TMP_DIR}/harness.sh"
```

- [ ] **Step 8: Run test to verify it fails before the implementation**

Run: `bash tests/hy2_update_preserves_manual_passwords.sh`
Expected: FAIL if update flow overwrites existing manually set HY2 or OBFS passwords.

- [ ] **Step 9: Write the test assertions**

```bash
output=$(cd "${TMP_DIR}" && bash ./harness.sh)

if [[ "${output}" != *"PASSWORD=manual-hy2-password"* ]]; then
  printf 'expected hy2 update to preserve manual password, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"OBFS_PASSWORD=manual-obfs-password"* ]]; then
  printf 'expected hy2 update to preserve manual obfs password, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 10: Commit**

```bash
git add tests/hy2_install_auto_generates_password_when_blank.sh tests/hy2_install_auto_generates_obfs_password_when_enabled.sh tests/hy2_update_preserves_manual_passwords.sh
git commit -m "test: cover hy2 secret generation defaults"
```

### Task 2: Implement HY2 Secret Helpers And Prompt Flow

**Files:**
- Modify: `install.sh`
- Test: `tests/hy2_install_auto_generates_password_when_blank.sh`
- Test: `tests/hy2_install_auto_generates_obfs_password_when_enabled.sh`
- Test: `tests/hy2_update_preserves_manual_passwords.sh`

- [ ] **Step 1: Add focused HY2 secret helper functions near `generate_random_token()`**

```bash
generate_hy2_secret() {
  local byte_length=${1:-18}
  local secret

  secret=$(openssl rand -base64 "${byte_length}" 2>/dev/null | tr -d '\n=' | tr '/+' '_-' || true)
  if [[ -z "${secret}" ]]; then
    secret=$(generate_random_token "" "${byte_length}")
  fi

  printf '%s' "${secret}"
}

ensure_hy2_password() {
  if [[ -z "${SB_HY2_PASSWORD}" ]]; then
    SB_HY2_PASSWORD=$(generate_hy2_secret 18)
  fi
}

ensure_hy2_obfs_password() {
  if [[ "${SB_HY2_OBFS_ENABLED}" != "y" ]]; then
    SB_HY2_OBFS_TYPE=""
    SB_HY2_OBFS_PASSWORD=""
    return 0
  fi

  [[ -z "${SB_HY2_OBFS_TYPE}" ]] && SB_HY2_OBFS_TYPE="salamander"
  [[ -z "${SB_HY2_OBFS_PASSWORD}" ]] && SB_HY2_OBFS_PASSWORD=$(generate_hy2_secret 18)
}
```

- [ ] **Step 2: Update the HY2 install prompt to advertise auto-generated secrets**

```bash
read -rp "[Hysteria2] 密码 (留空自动生成高强度密码): " in_password
[[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"

read -rp "[Hysteria2] 是否启用 Salamander 混淆 [y/n] (默认 n): " in_obfs
SB_HY2_OBFS_ENABLED=${in_obfs:-"n"}
if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
  SB_HY2_OBFS_TYPE="salamander"
  read -rp "[Hysteria2] 混淆密码 (留空自动生成高强度密码): " in_obfs_password
  [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
fi
```

- [ ] **Step 3: Update the HY2 update prompt to support explicit regeneration without silent overwrites**

```bash
read -rp "密码 (当前: 留空隐藏, 输入 keep 保持，输入 regen 自动重置): " in_password
case "${in_password}" in
  "")
    ;;
  keep)
    ;;
  regen)
    SB_HY2_PASSWORD=""
    ;;
  *)
    SB_HY2_PASSWORD="${in_password}"
    ;;
esac

read -rp "是否启用 Salamander 混淆 [y/n] (当前: ${SB_HY2_OBFS_ENABLED}, 留空保持): " in_obfs
if [[ -n "${in_obfs}" ]]; then
  SB_HY2_OBFS_ENABLED="${in_obfs}"
fi

if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
  read -rp "混淆密码 (当前: 留空隐藏, 输入 keep 保持，输入 regen 自动重置): " in_obfs_password
  case "${in_obfs_password}" in
    "")
      ;;
    keep)
      ;;
    regen)
      SB_HY2_OBFS_PASSWORD=""
      ;;
    *)
      SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
      ;;
  esac
  [[ -z "${SB_HY2_OBFS_TYPE}" ]] && SB_HY2_OBFS_TYPE="salamander"
else
  SB_HY2_OBFS_TYPE=""
  SB_HY2_OBFS_PASSWORD=""
fi
```

- [ ] **Step 4: Call the helper functions from the existing HY2 material normalization block**

```bash
ensure_hy2_materials() {
  if [[ -z "${SB_HY2_DOMAIN}" ]]; then
    log_error "Hysteria2 域名不能为空。"
  fi

  ensure_hy2_password
  ensure_hy2_obfs_password

  if [[ "${SB_HY2_TLS_MODE}" == "manual" ]]; then
    # existing manual TLS validation remains here
```

- [ ] **Step 5: Run focused tests to verify the implementation**

Run:
`bash tests/hy2_install_auto_generates_password_when_blank.sh`
`bash tests/hy2_install_auto_generates_obfs_password_when_enabled.sh`
`bash tests/hy2_update_preserves_manual_passwords.sh`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/hy2_install_auto_generates_password_when_blank.sh tests/hy2_install_auto_generates_obfs_password_when_enabled.sh tests/hy2_update_preserves_manual_passwords.sh
git commit -m "feat: strengthen hy2 secret defaults"
```

### Task 3: Cover Link Output And State Persistence

**Files:**
- Create: `tests/hy2_link_includes_generated_obfs_params.sh`
- Create: `tests/hy2_state_persists_generated_secrets.sh`
- Modify: `install.sh`
- Test: `tests/hy2_connection_info_shows_summary_and_link.sh`

- [ ] **Step 1: Write the failing test for OBFS parameters in the share link**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

source "${REPO_ROOT}/install.sh"

SB_PROTOCOL="hy2"
SB_NODE_NAME="hy2_test-host"
SB_PORT="443"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_PASSWORD="generated-hy2-password"
SB_HY2_OBFS_ENABLED="y"
SB_HY2_OBFS_TYPE="salamander"
SB_HY2_OBFS_PASSWORD="generated-obfs-password"

link=$(build_hy2_link "198.51.100.20")

if [[ "${link}" != *"obfs=salamander"* ]]; then
  printf 'expected hy2 link to include obfs type, got:\n%s\n' "${link}" >&2
  exit 1
fi

if [[ "${link}" != *"obfs-password=generated-obfs-password"* ]]; then
  printf 'expected hy2 link to include obfs password, got:\n%s\n' "${link}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it passes or tighten expectations if needed**

Run: `bash tests/hy2_link_includes_generated_obfs_params.sh`
Expected: PASS after confirming the link builder remains the single source of truth.

- [ ] **Step 3: Write the failing test for persisted generated secrets**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

source "${REPO_ROOT}/install.sh"

export SB_PROTOCOL_STATE_DIR="${TMP_DIR}/protocols"
mkdir -p "${SB_PROTOCOL_STATE_DIR}"

set_protocol_defaults "hy2"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_TLS_MODE="manual"
SB_HY2_CERT_PATH="/etc/ssl/certs/hy2.pem"
SB_HY2_KEY_PATH="/etc/ssl/private/hy2.key"
SB_HY2_OBFS_ENABLED="y"

ensure_hy2_password
ensure_hy2_obfs_password
save_hy2_state

if ! grep -Eq '^PASSWORD=.+$' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 state to persist generated password, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if ! grep -Eq '^OBFS_PASSWORD=.+$' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 state to persist generated obfs password, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi
```

- [ ] **Step 4: Run state and output tests**

Run:
`bash tests/hy2_state_persists_generated_secrets.sh`
`bash tests/hy2_connection_info_shows_summary_and_link.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/hy2_link_includes_generated_obfs_params.sh tests/hy2_state_persists_generated_secrets.sh install.sh
git commit -m "test: cover hy2 secret persistence and link output"
```

### Task 4: Update Version Metadata And Documentation

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Test: `tests/version_metadata_is_consistent.sh`
- Test: `tests/readme_mentions_current_versions.sh`

- [ ] **Step 1: Bump the single-turn script version once**

```bash
readonly SCRIPT_VERSION="2026042221"
```

- [ ] **Step 2: Update README version references and any HY2 prompt text that documents blank-password behavior**

```markdown
- `Hysteria2` installs now auto-generate strong passwords by default and keep Salamander OBFS optional.
```

- [ ] **Step 3: Run metadata checks**

Run:
`bash tests/version_metadata_is_consistent.sh`
`bash tests/readme_mentions_current_versions.sh`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add install.sh README.md
git commit -m "docs: update hy2 secret defaults documentation"
```

### Task 5: Run Full Local Verification And Remote HY2 Smoke Test

**Files:**
- Modify: `dev/verification-runs/` (generated artifacts only, ignored)
- Test: `tests/hy2_install_auto_generates_password_when_blank.sh`
- Test: `tests/hy2_install_auto_generates_obfs_password_when_enabled.sh`
- Test: `tests/hy2_update_preserves_manual_passwords.sh`
- Test: `tests/hy2_link_includes_generated_obfs_params.sh`
- Test: `tests/hy2_state_persists_generated_secrets.sh`
- Test: `tests/hy2_connection_info_shows_summary_and_link.sh`
- Test: `tests/multi_protocol_hy2_config_generation.sh`
- Test: `tests/hy2_config_sets_h3_alpn.sh`
- Test: `tests/hy2_acme_config_sets_data_directory.sh`
- Test: `tests/hy2_default_masquerade_is_cloudflare.sh`
- Test: `tests/version_metadata_is_consistent.sh`
- Test: `tests/readme_mentions_current_versions.sh`

- [ ] **Step 1: Run the focused local regression set**

Run:
`bash tests/hy2_install_auto_generates_password_when_blank.sh`
`bash tests/hy2_install_auto_generates_obfs_password_when_enabled.sh`
`bash tests/hy2_update_preserves_manual_passwords.sh`
`bash tests/hy2_link_includes_generated_obfs_params.sh`
`bash tests/hy2_state_persists_generated_secrets.sh`
`bash tests/hy2_connection_info_shows_summary_and_link.sh`
`bash tests/multi_protocol_hy2_config_generation.sh`
`bash tests/hy2_config_sets_h3_alpn.sh`
`bash tests/hy2_acme_config_sets_data_directory.sh`
`bash tests/hy2_default_masquerade_is_cloudflare.sh`
`bash tests/version_metadata_is_consistent.sh`
`bash tests/readme_mentions_current_versions.sh`

Expected: all PASS

- [ ] **Step 2: Run remote verification because `install.sh` changed**

Run: `VERIFY_SKIP_LOCAL_TESTS=1 bash dev/verification/run.sh --changed-file install.sh`
Expected: `remote_status=success` in the new `dev/verification-runs/<timestamp>/summary.log`

- [ ] **Step 3: Run an explicit HY2 install on `sing-box-test` with defaults and confirm generated secrets are non-empty**

Run:

```bash
ssh -o BatchMode=yes sing-box-test '
  bash /root/sing-box-vps/install.sh <<'"'"'MENU'"'"'
1
3
rn-us-lax.knowsky404.com



n
1

0
MENU
  source /root/sing-box-vps/protocols/hy2.env
  printf "PASSWORD=%s\nOBFS_ENABLED=%s\nOBFS_PASSWORD=%s\n" "$PASSWORD" "${OBFS_ENABLED:-n}" "${OBFS_PASSWORD:-}"
'
```

Expected:
- `PASSWORD` is non-empty and not a weak placeholder
- `OBFS_ENABLED=n`
- `OBFS_PASSWORD=` is empty

- [ ] **Step 4: Run an explicit HY2 reconfigure on `sing-box-test` with OBFS enabled and confirm link output includes the generated OBFS password**

Run:

```bash
ssh -o BatchMode=yes sing-box-test '
  bash /root/sing-box-vps/install.sh <<'"'"'MENU'"'"'
2
1




y
regen





0
MENU
  source /root/sing-box-vps/protocols/hy2.env
  printf "PASSWORD=%s\nOBFS_ENABLED=%s\nOBFS_PASSWORD=%s\n" "$PASSWORD" "${OBFS_ENABLED:-n}" "${OBFS_PASSWORD:-}"
'
```

Expected:
- `OBFS_ENABLED=y`
- `OBFS_PASSWORD` is non-empty
- subsequent node output includes `obfs=salamander` and `obfs-password=...`

- [ ] **Step 5: Commit**

```bash
git add install.sh README.md tests/hy2_install_auto_generates_password_when_blank.sh tests/hy2_install_auto_generates_obfs_password_when_enabled.sh tests/hy2_update_preserves_manual_passwords.sh tests/hy2_link_includes_generated_obfs_params.sh tests/hy2_state_persists_generated_secrets.sh
git commit -m "test: verify hy2 random secrets end to end"
```
