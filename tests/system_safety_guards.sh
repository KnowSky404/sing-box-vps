#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
SYSCTL_CONF="${TMP_DIR}/sysctl.conf"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e "s|/etc/sysctl.conf|${SYSCTL_CONF}|g" \
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sysctl" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "net.ipv4.tcp_congestion_control" ]]; then
  printf 'net.ipv4.tcp_congestion_control = cubic\n'
  exit 0
fi
if [[ "\${1:-}" == "-p" ]]; then
  printf '%s\n' "\${2:-}" > "${TMP_DIR}/sysctl-p.path"
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/bin/sysctl"

cat > "${TMP_DIR}/bin/ss" <<'EOF'
#!/usr/bin/env bash
printf 'tcp LISTEN 0 4096 0.0.0.0:443 0.0.0.0:* users:(("nginx",pid=1234,fd=6))\n'
EOF
chmod +x "${TMP_DIR}/bin/ss"

cat > "${TMP_DIR}/bin/kill" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TMP_DIR}/kill.log"
exit 0
EOF
chmod +x "${TMP_DIR}/bin/kill"

cat > "${TMP_DIR}/bin/ufw" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "status" ]]; then
  printf 'Status: inactive\n'
fi
EOF
chmod +x "${TMP_DIR}/bin/ufw"

cat > "${TMP_DIR}/bin/iptables" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TMP_DIR}/iptables.log"
if [[ "\${1:-}" == "-C" && "\$*" == *"--dport 443"* && "\$*" == *"-p tcp"* ]]; then
  exit 0
fi
if [[ "\${1:-}" == "-C" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "${TMP_DIR}/bin/iptables"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${SYSCTL_CONF}" <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=cubic
EOF

enable_bbr >/dev/null

if [[ "$(grep -c '^net.core.default_qdisc=' "${SYSCTL_CONF}")" != "1" ]]; then
  printf 'expected default_qdisc to remain single assignment\n' >&2
  exit 1
fi
if [[ "$(grep -c '^net.ipv4.tcp_congestion_control=' "${SYSCTL_CONF}")" != "1" ]]; then
  printf 'expected tcp_congestion_control to remain single assignment\n' >&2
  exit 1
fi
if ! grep -Fxq 'net.ipv4.tcp_congestion_control=bbr' "${SYSCTL_CONF}"; then
  printf 'expected tcp_congestion_control to be updated to bbr\n' >&2
  exit 1
fi

open_firewall_port 443 >/dev/null
if grep -Fqx -- '-I INPUT -p tcp --dport 443 -j ACCEPT' "${TMP_DIR}/iptables.log"; then
  printf 'expected existing tcp iptables rule not to be inserted again\n' >&2
  exit 1
fi
grep -Fqx -- '-I INPUT -p udp --dport 443 -j ACCEPT' "${TMP_DIR}/iptables.log"

SB_PORT=443
check_port_conflict 443 <<'EOF' >/dev/null
1
EOF

if [[ -f "${TMP_DIR}/kill.log" ]]; then
  printf 'expected port conflict option 1 not to kill the occupying process directly\n' >&2
  exit 1
fi
