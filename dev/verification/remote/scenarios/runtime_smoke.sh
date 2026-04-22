#!/usr/bin/env bash

set -euo pipefail

printf 'SCENARIO=runtime_smoke\n'
printf 'SERVICE_ACTIVE=%s\n' "$(systemctl is-active sing-box)"
systemctl status sing-box --no-pager || true
journalctl -u sing-box -n 100 --no-pager || true
sing-box check -c /root/sing-box-vps/config.json
ss -lntp || true
