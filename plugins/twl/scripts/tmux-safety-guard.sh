#!/usr/bin/env bash
# tmux-safety-guard.sh — tmux burst-kill safety lint
#
# Issue #1360: tmux server burst-kill 防止 lint。
#
# 検査項目:
#   L-1: scripts/ / skills/ 配下の本番 bash で `tmux kill-window` の直接呼び出しを禁止。
#        `plugins/twl/scripts/lib/tmux-window-kill.sh::safe_kill_window` ヘルパー経由を要求する。
#   L-2: `safe_kill_window` ヘルパー本体に `sleep 1`（または SAFE_KILL_WINDOW_SLEEP 変数経由）
#        の挿入がない場合は warning。
#
# L-1 除外対象:
#   - scripts/lib/tmux-window-kill.sh（ヘルパー本体）
#   - scripts/tmux-safety-guard.sh（本スクリプト自身）
#   - *.bats / test_*.py / *_test.py（テストファイル：直接呼び出しを assertion 等で含むため）
#   - *.md（ドキュメント：言及を含むため）
#
# 使い方:
#   bash plugins/twl/scripts/tmux-safety-guard.sh           # full lint
#   bash plugins/twl/scripts/tmux-safety-guard.sh --quiet   # 失敗箇所のみ出力
#
# Exit code:
#   0  = pass
#   1  = lint violation
#   2  = usage error

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q) QUIET=1 ;;
    --help|-h)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "usage error: unknown flag '$1'" >&2; exit 2 ;;
  esac
  shift
done

FAIL_COUNT=0
_fail() {
  echo "FAIL: $*" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}
_ok() {
  [[ $QUIET -eq 1 ]] || echo "ok: $*"
}

# ---------------------------------------------------------------------------
# L-1: scripts/ / skills/ 配下の本番 bash に `tmux kill-window` 直接呼び出しなし
# ---------------------------------------------------------------------------

# 検査対象: scripts/, skills/ 配下のシェルスクリプト
# 除外: ヘルパー本体、本スクリプト、テスト、ドキュメント
_scan_dirs=()
[[ -d "${REPO_ROOT}/scripts" ]] && _scan_dirs+=("${REPO_ROOT}/scripts")
[[ -d "${REPO_ROOT}/skills" ]]  && _scan_dirs+=("${REPO_ROOT}/skills")

if [[ ${#_scan_dirs[@]} -eq 0 ]]; then
  _violations=""
else
  _violations=$(grep -RnE 'tmux[[:space:]]+kill-window' "${_scan_dirs[@]}" 2>/dev/null \
    | grep -v 'scripts/lib/tmux-window-kill.sh' \
    | grep -v 'scripts/tmux-safety-guard.sh' \
    | grep -vE '\.(bats|md)(:|$)' \
    | grep -vE 'test_.*\.py|_test\.py' \
    || true)
fi

if [[ -n "$_violations" ]]; then
  while IFS= read -r line; do
    _fail "L-1: tmux kill-window の直接呼び出し検出 — safe_kill_window 経由にしてください: $line"
  done <<< "$_violations"
else
  _ok "L-1: scripts/ + skills/ 配下の本番 bash に tmux kill-window 直接呼び出しなし（safe_kill_window 経由）"
fi

# ---------------------------------------------------------------------------
# L-2: safe_kill_window ヘルパー本体に sleep 1（または SAFE_KILL_WINDOW_SLEEP）あり
# ---------------------------------------------------------------------------

HELPER="${REPO_ROOT}/scripts/lib/tmux-window-kill.sh"
if [[ ! -f "$HELPER" ]]; then
  _fail "L-2: helper ${HELPER} が見つかりません"
else
  # kill-window 直後の sleep（同じ if ブロック内）を検出
  # 単純化: helper 全体で kill-window と sleep が両方含まれていれば OK
  if grep -qE 'tmux[[:space:]]+kill-window' "$HELPER" \
     && grep -qE 'sleep[[:space:]]+("?\$\{?SAFE_KILL_WINDOW_SLEEP|[0-9])' "$HELPER"; then
    _ok "L-2: safe_kill_window 内に kill-window + sleep の組み合わせあり"
  else
    _fail "L-2: ${HELPER} に kill-window 直後の sleep が見つかりません（Issue #1360 burst-kill 対策）"
  fi
fi

# ---------------------------------------------------------------------------
# 結果サマリ
# ---------------------------------------------------------------------------

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "tmux-safety-guard: ${FAIL_COUNT} violation(s)" >&2
  exit 1
fi

[[ $QUIET -eq 1 ]] || echo "tmux-safety-guard: PASS"
exit 0
