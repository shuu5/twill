#!/usr/bin/env bash
# merge-gate-check-spawn.sh - spawn 完了確認（merge-gate Step: spawn 完了確認）
#
# 全 specialist の spawn 完了を確認する。未 spawn があれば ERROR を出力して exit 1。
# 環境変数 MANIFEST_FILE, SPAWNED_FILE が必要（merge-gate-build-manifest.sh で設定済み）。
#
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-spawn.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${MANIFEST_FILE:-}" && -f "${MANIFEST_FILE:-}" ]]; then
  MISSING=$(comm -23 \
    <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$' | sed 's|^twl:twl:||' | sort -u) \
    <(sort -u "${SPAWNED_FILE:-/dev/null}" 2>/dev/null || true))
  if [[ -n "$MISSING" ]]; then
    echo "ERROR: 以下の specialist が未 spawn:"
    echo "$MISSING"
    echo "未 spawn の specialist を追加 spawn してから結果集約に進むこと"
    exit 1
  fi
  echo "✓ 全 specialist spawn 完了確認済み"
fi

# --- JSONL 独立検証（LLM 自己申告に依存しない specialist completeness 確認）---
# MANIFEST_FILE ブロック外に配置し、chain 外実行時にも specialist 監査を走らせる
_audit_script="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}/scripts/specialist-audit.sh"
if [[ -f "$_audit_script" ]]; then
  # ISSUE_NUM を解決（resolve-issue-num.sh 経由、失敗時は空文字）
  _issue_num="${ISSUE_NUM:-}"
  if [[ -z "$_issue_num" ]]; then
    _resolver="${SCRIPT_DIR}/resolve-issue-num.sh"
    if [[ -f "$_resolver" ]]; then
      # shellcheck disable=SC1090
      source "$_resolver" 2>/dev/null || true
      if declare -f resolve_issue_num >/dev/null 2>&1; then
        _issue_num=$(resolve_issue_num 2>/dev/null || echo "")
      fi
    fi
  fi

  # quick ラベル判定（IS_QUICK 環境変数または .autopilot/issues/issue-N.json 参照）
  _quick_flag=""
  if [[ "${IS_QUICK:-false}" == "true" ]]; then
    _quick_flag="--quick"
  elif [[ -n "$_issue_num" ]]; then
    _is_quick=$(python3 -m twl.autopilot.state read --type issue --issue "$_issue_num" --field is_quick 2>/dev/null || echo "false")
    [[ "$_is_quick" == "true" ]] && _quick_flag="--quick"
  fi

  # --manifest-file を渡して pr-review-manifest.sh の二重呼び出しを回避
  # 配列で引数を構築してワードスプリットを防止
  _manifest_args=()
  [[ -n "${MANIFEST_FILE:-}" && -f "${MANIFEST_FILE:-}" ]] && _manifest_args=(--manifest-file "${MANIFEST_FILE}")
  _quick_args=()
  [[ "$_quick_flag" == "--quick" ]] && _quick_args=(--quick)

  _audit_exit=0
  if [[ -n "$_issue_num" ]]; then
    bash "$_audit_script" --issue "$_issue_num" --mode merge-gate \
      "${_manifest_args[@]+"${_manifest_args[@]}"}" "${_quick_args[@]+"${_quick_args[@]}"}" 2>/dev/null || _audit_exit=$?
  else
    echo "WARN: specialist-audit: Issue 番号が解決できないためスキップ" >&2
  fi

  if [[ $_audit_exit -ne 0 ]]; then
    echo "REJECT: specialist-audit FAIL (exit=${_audit_exit})" >&2
    exit $_audit_exit
  fi
  echo "✓ specialist-audit: PASS"
else
  echo "WARN: specialist-audit.sh が見つかりません: ${_audit_script}" >&2
fi
