#!/usr/bin/env bash
# PreToolUse hook: PR 作成段階で test-only diff を検出して block (Issue #1633 / ADR-039)
#
# 動作:
#   1. tool_name が "Bash" 以外 → no-op (exit 0)
#   2. command に gh pr create を含まない → no-op (exit 0)
#      (pr-create-helper.sh 経由の実行も同一 Bash hook で捕捉される)
#   3. bypass チェック (SKIP_PRE_PR_GATE=1 + SKIP_PRE_PR_GATE_REASON='<reason>')
#      - SKIP=1 + REASON 非空 → audit log 記録 + 通過
#      - SKIP=1 + REASON 不在 → deny (REASON 必須化、issue-create-gate と同形式)
#   4. git diff で変更ファイル取得 → test-only か判定
#   5. test-only かつ Issue label に tdd-followup / test-only が不在 → deny
#   6. それ以外 → 通過
#
# 既存 merge-gate-check-red-only.sh (#1626 / merge 段階) との関係:
#   - merge-gate-check-red-only.sh: merge 試行時に red-only label + follow-up 不在を REJECT
#   - 本 hook (pre-pr-gate): PR 作成試行時に test-only diff を ABORT
#   - 同一の「実装ファイル不在」判定を異なる event horizon で実行する Defense in Depth
#
# 公式仕様:
#   - https://code.claude.com/docs/en/hooks
#   - JSON deny + exit 0 (permissionDecision: "deny") を採用
#     (exit 2 + stderr は緊急用、permissionDecisionReason / additionalContext と組み合わせ不可)

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

# JSON パース失敗 → no-op
if ! printf '%s' "$payload" | jq empty 2>/dev/null; then
  exit 0
fi

# Bash tool 以外 → no-op
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

CMD=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
if [[ -z "$CMD" ]]; then
  exit 0
fi

# gh pr create にマッチしない → no-op (gh pr merge 等は別 hook が担当)
if ! printf '%s' "$CMD" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+create\b'; then
  exit 0
fi

LOG_FILE="/tmp/pre-pr-gate-bypass.log"
log_event() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

emit_deny() {
  local reason="$1"
  jq -nc --arg reason "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

# === bypass: SKIP_PRE_PR_GATE=1 + SKIP_PRE_PR_GATE_REASON='<reason>' ===
# 簡略化 (M1 fix): env var prefix chain の strict 検証は audit log で担保するため、
# token boundary だけ確認すれば十分。multiline コマンドにも対応 (H4 fix)。
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])SKIP_PRE_PR_GATE=1([[:space:]]|$)'; then
  # REASON 抽出: ダブルクォート優先 (`'` を含む reason に対応、H2 fix)、シングルクォートは fallback
  REASON=$(printf '%s' "$CMD" | grep -oP 'SKIP_PRE_PR_GATE_REASON="[^"]+"' | head -1 \
    | sed 's/^SKIP_PRE_PR_GATE_REASON="//;s/"$//' || echo "")
  if [[ -z "$REASON" ]]; then
    # シングルクォート fallback (REASON 内の `'` は禁止 — エスケープ不可、ドキュメントで明示)
    REASON=$(printf '%s' "$CMD" | grep -oP "SKIP_PRE_PR_GATE_REASON='[^']+'" | head -1 \
      | sed "s/^SKIP_PRE_PR_GATE_REASON='//;s/'$//" || echo "")
  fi
  if [[ -z "$REASON" ]]; then
    emit_deny "PRE-PR-GATE BLOCK: SKIP_PRE_PR_GATE=1 が指定されていますが SKIP_PRE_PR_GATE_REASON が不在です。

bypass には reason が必須です:
  SKIP_PRE_PR_GATE=1 SKIP_PRE_PR_GATE_REASON='<具体的な理由>' gh pr create ...
または (REASON に \` を含む場合):
  SKIP_PRE_PR_GATE=1 SKIP_PRE_PR_GATE_REASON=\"<理由>\" gh pr create ...

audit log: ${LOG_FILE} (REASON 必須化、Issue #1633 / ADR-039)"
  fi
  user="${USER:-$(id -un 2>/dev/null || echo unknown)}"
  log_event "BYPASS user=${user} reason=${REASON} cmd_hash=$(printf '%s' "$CMD" | sha256sum | head -c8)"
  exit 0
fi

# === test-only diff 検出 ===
_is_test_file() {
  local f="$1"
  [[ "$f" == *.bats ]] && return 0
  [[ "$f" == *test_*.py ]] && return 0
  [[ "$f" == *_test.py ]] && return 0
  [[ "$f" == *.test.ts ]] && return 0
  [[ "$f" == *.spec.ts ]] && return 0
  [[ "$f" == *.test.js ]] && return 0
  [[ "$f" == *.spec.js ]] && return 0
  [[ "$f" == */tests/* ]] && return 0
  [[ "$f" == */test/* ]] && return 0
  [[ "$f" == *ac-test-mapping*.yaml ]] && return 0
  return 1
}

# 変更ファイル取得 (二段、M3 fix: 意図を明示)
# Primary: git diff --name-only origin/main (PR スコープを正確に反映)
# Fallback: git diff --name-only HEAD (origin/main 到達不能時、unstaged changes の検出)
#   注: HEAD fallback は PR scope と乖離する可能性があるが、何も検出しないより安全。
CHANGED_FILES=""
if _files=$(git diff --name-only origin/main 2>/dev/null) && [[ -n "$_files" ]]; then
  CHANGED_FILES="$_files"
elif _files=$(git diff --name-only HEAD 2>/dev/null) && [[ -n "$_files" ]]; then
  CHANGED_FILES="$_files"
fi

# diff 取得失敗 (両方空 = 真に変更なし or git repo 外) → graceful passthrough
# Rationale: hook を fail-closed にすると非 git ディレクトリや初期コミットで PR 作成が
# 完全不可になる。fail-open は audit log で観測可能、悪用は merge-gate (#1626) で catch される。
if [[ -z "$CHANGED_FILES" ]]; then
  log_event "ALLOW git diff empty (PR 状態未確定 or 非 git 環境) cmd_hash=$(printf '%s' "$CMD" | sha256sum | head -c8)"
  exit 0
fi

# 実装ファイルが 1 件でもあれば通過
has_impl_file=false
test_files_list=""
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if _is_test_file "$file"; then
    test_files_list="${test_files_list}${file}\n"
  else
    has_impl_file=true
  fi
done <<< "$CHANGED_FILES"

if $has_impl_file; then
  exit 0
fi

# === test-only diff 確定 ===
# Issue 番号と label を取得して allowlist チェック
issue_num=""
if command -v bash >/dev/null 2>&1 && [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-issue-num.sh" ]]; then
  issue_num=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || echo "")
fi
# fallback: branch 名から Issue 番号抽出 (feat/1633-... / tech-debt/1633-... → 1633、H4 fix)
if [[ -z "$issue_num" ]]; then
  branch=$(git branch --show-current 2>/dev/null || echo "")
  if [[ "$branch" =~ ^[a-z][a-z0-9-]*/([0-9]+) ]]; then
    issue_num="${BASH_REMATCH[1]}"
  fi
fi

# 数値検証 (C2 fix: command injection 防止、resolve-issue-num.sh の出力が攻撃者制御の場合の防御)
if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
  issue_num=""
fi

# Issue label 取得 (gh CLI、エラー時は空)
labels=""
if [[ -n "$issue_num" ]] && command -v gh >/dev/null 2>&1; then
  labels=$(gh issue view "$issue_num" --json labels --jq '.labels[].name' 2>/dev/null || echo "")
fi

# allowlist label に tdd-followup / test-only があれば通過
if printf '%s' "$labels" | grep -qE '^(tdd-followup|test-only)$'; then
  log_event "ALLOW test-only diff with allowlist label (issue=#${issue_num})"
  exit 0
fi

# === deny 確定 ===
log_event "DENY test-only diff (issue=#${issue_num:-unknown}) cmd_hash=$(printf '%s' "$CMD" | sha256sum | head -c8)"

# 変更ファイルリストを deny message に含める (上限 10 件、UX 配慮、M2 fix: 簡略化)
files_summary=$(printf '%b' "$test_files_list" | head -10 | sed 's/^/  - /')

DENY_MSG="PRE-PR-GATE BLOCK: test-only diff を検出しました (実装ファイル不在)。

Issue: #${issue_num:-unknown}
allowlist label (tdd-followup / test-only): 不在
変更ファイル: ${files_summary}

【正規の手順 (推奨)】
  workflow-test-ready の green-impl step で GREEN 実装まで完了してから gh pr create してください。
    bash \$CR llm-delegate \"green-impl\" \$ISSUE_NUM
    # commands/green-impl.md を Read → 実行 → tdd-green-guard.sh 検証

【緊急 bypass】 (audit log に記録、濫用は監査対象)
  SKIP_PRE_PR_GATE=1 SKIP_PRE_PR_GATE_REASON='<具体的な理由>' gh pr create ...

【allowlist label】
  tdd-followup または test-only label を Issue に付与した場合は本 gate を通過します。

詳細: Issue #1633 / ADR-039 / 不変条件 S (#1626 から事前抑止に格上げ)
audit log: ${LOG_FILE}"

emit_deny "$DENY_MSG"
