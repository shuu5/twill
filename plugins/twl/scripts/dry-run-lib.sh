#!/usr/bin/env bash
# dry-run-lib.sh - Issue #144 / Phase 4-A Layer 2
#
# workflow-* skill 配下の dry-run.sh が共有する trace emit ヘルパー。
# LLM ステップや破壊的副作用を持つステップ（auto-merge, worktree-create 等）は
# chain-runner.sh の dispatch を経由できないため、本ヘルパーで TWL_CHAIN_TRACE に
# 直接 start/end イベントを書き込む。フォーマットは chain-runner.sh の trace_event() と
# 完全一致させ、assert_trace_order/contains が機械的・LLM 両方を区別なく扱えるようにする。

# trace ファイルにイベントを 1 件書き込む（内部実装）
# Args: <step> <phase> [exit_code]
_dry_run_emit_event() {
  local step="$1" phase="$2" exit_code="${3:-}"
  [[ -z "${TWL_CHAIN_TRACE:-}" ]] && return 0
  local trace_file="$TWL_CHAIN_TRACE"
  case "$trace_file" in *..*) return 0 ;; esac
  mkdir -p "$(dirname "$trace_file")" 2>/dev/null || return 0
  local ts
  ts=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  local exit_field
  if [[ -z "$exit_code" ]]; then exit_field="null"; else exit_field="$exit_code"; fi
  printf '{"step":"%s","phase":"%s","ts":"%s","exit_code":%s,"pid":%s}\n' \
    "$step" "$phase" "$ts" "$exit_field" "$$" >> "$trace_file" 2>/dev/null || true
}

# LLM / 破壊的ステップ用の trace emit。chain-runner を経由せず start/end を一気に書く。
# Args: <step> [exit_code=0]
dry_run_emit_step() {
  local step="$1" exit_code="${2:-0}"
  _dry_run_emit_event "$step" "start"
  _dry_run_emit_event "$step" "end" "$exit_code"
}
