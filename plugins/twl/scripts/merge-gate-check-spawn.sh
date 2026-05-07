#!/usr/bin/env bash
# merge-gate-check-spawn.sh - spawn 完了確認（merge-gate Step: spawn 完了確認）
#
# 全 specialist の spawn 完了を確認する。未 spawn があれば ERROR を出力して exit 1。
# findings.yaml 存在ベース判定（#1481 AC-2: 自己申告 path を deprecate）。
#
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-spawn.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${MANIFEST_FILE:-}" && -f "${MANIFEST_FILE:-}" ]]; then
  # findings.yaml 存在ベース判定（#1481 AC-2）
  # CONTROLLER_ISSUE_DIR/OUT/<specialist>/findings.yaml の存在で spawn 完了を確認する
  _controller_issue_dir="${CONTROLLER_ISSUE_DIR:-}"
  _missing=()
  while IFS= read -r _spec; do
    [[ -z "$_spec" || "$_spec" == \#* ]] && continue
    _spec_name="${_spec#twl:twl:}"
    if [[ -n "$_controller_issue_dir" ]]; then
      _findings="${_controller_issue_dir}/OUT/${_spec_name}/findings.yaml"
      if [[ ! -f "$_findings" ]]; then
        _missing+=("$_spec_name")
      fi
    fi
  done < <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$')
  if [[ ${#_missing[@]} -gt 0 ]]; then
    echo "ERROR: 以下の specialist の findings.yaml が未生成:"
    printf '%s\n' "${_missing[@]}"
    echo "未 spawn の specialist を追加 spawn してから結果集約に進むこと"
    exit 1
  fi
  echo "✓ 全 specialist spawn 完了確認済み（findings.yaml ベース）"
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

  # --manifest-file を渡して pr-review-manifest.sh の二重呼び出しを回避
  # 配列で引数を構築してワードスプリットを防止
  _manifest_args=()
  [[ -n "${MANIFEST_FILE:-}" && -f "${MANIFEST_FILE:-}" ]] && _manifest_args=(--manifest-file "${MANIFEST_FILE}")

  # --codex-session-dir: codex セッションログの場所（HARD FAIL 経路の活性化、#1507 AC-8/B3）
  # --controller-issue-dir: OUT/ ファイル存在確認用（#1507 AC-8）
  _codex_session_dir="${CODEX_SESSION_DIR:-${HOME}/.codex/sessions/$(date +%Y/%m 2>/dev/null || echo "")}"
  _controller_issue_dir_arg="${CONTROLLER_ISSUE_DIR:-}"

  _codex_args=()
  [[ -n "$_codex_session_dir" ]] && _codex_args+=(--codex-session-dir "$_codex_session_dir")
  [[ -n "$_controller_issue_dir_arg" ]] && _codex_args+=(--controller-issue-dir "$_controller_issue_dir_arg")

  _audit_exit=0
  if [[ -n "$_issue_num" ]]; then
    bash "$_audit_script" --issue "$_issue_num" --mode merge-gate \
      "${_manifest_args[@]+"${_manifest_args[@]}"}" \
      "${_codex_args[@]+"${_codex_args[@]}"}" 2>/dev/null || _audit_exit=$?
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
