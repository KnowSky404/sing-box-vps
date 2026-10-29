#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
export SB_PROGRESS_INTERVAL_SECONDS=1
slow_json() { sleep 2; printf '{"ok":true}\n'; }
result=$(run_with_progress '校验测试' slow_json 2>"${TMP_DIR}/progress")
[[ "${result}" == '{"ok":true}' ]]
grep -Fq '已等待 1 秒' "${TMP_DIR}/progress"
grep -Fq '完成' "${TMP_DIR}/progress"
if run_with_progress '失败测试' bash -c 'exit 23' >"${TMP_DIR}/stdout" 2>"${TMP_DIR}/failure"; then exit 1; else [[ $? == 23 ]]; fi
[[ ! -s "${TMP_DIR}/stdout" ]]
grep -Fq '状态 23' "${TMP_DIR}/failure"
# The command must inherit stdin and prompts must remain usable.
[[ "$(run_with_progress '输入测试' cat <<< 'forwarded' 2>"${TMP_DIR}/stdin.log")" == forwarded ]]
# Interruption reaches the worker and waits for its rollback/cleanup trap.
cat > "${TMP_DIR}/worker.sh" <<'WORKER'
#!/usr/bin/env bash
set -euo pipefail
trap 'printf rolled-back > "$1"; exit 143' TERM
printf '%s' "$$" > "$2"
while :; do sleep 0.1; done
WORKER
run_with_progress '中断测试' bash "${TMP_DIR}/worker.sh" "${TMP_DIR}/rollback" "${TMP_DIR}/ready" >"${TMP_DIR}/interrupt.out" 2>"${TMP_DIR}/interrupt.err" &
wrapper=$!
for ((attempt=0; attempt<100; attempt++)); do [[ ! -f "${TMP_DIR}/ready" ]] || break; sleep 0.05; done
[[ -f "${TMP_DIR}/ready" ]]
kill -TERM "$(cat "${TMP_DIR}/ready")"
wait "${wrapper}" && exit 1 || [[ $? == 143 ]]
[[ "$(cat "${TMP_DIR}/rollback")" == rolled-back ]]
# A caller cleanup trap must run once in its owner, never in the timer.
(
  trap 'printf "%s\n" caller-cleanup >> "${TMP_DIR}/caller-exit"' EXIT
  run_with_progress 'EXIT 隔离测试' sleep 2 >"${TMP_DIR}/exit.out" 2>"${TMP_DIR}/exit.err"
  [[ ! -e "${TMP_DIR}/caller-exit" ]]
)
[[ "$(wc -l < "${TMP_DIR}/caller-exit")" == 1 ]]
printf 'operation progress: heartbeat, stdout, exit status, stdin and signal cleanup passed\n'
