#!/usr/bin/env bash
# PreToolUse hook: git commit 時に twl --validate を実行する commit gate
#
# Claude Code の PreToolUse フェーズで呼び出される。
# Bash ツールの実行前に $TOOL_INPUT_command を確認し、
# git commit を含む場合のみ twl --validate を実行する。
#
# 終了コード:
#   0 — 通過（commit を許可）
#   2 — ブロック（violations あり、commit を拒否）
#
# 環境変数:
#   TOOL_INPUT_command     実行しようとしている Bash コマンド文字列（Claude Code が注入）
#   TWL_SKIP_COMMIT_GATE   1 に設定するとゲートをバイパス（Issue E 完了前の安全装置）
#   PLUGINS_TWL_DIR        テスト専用オーバーライド（BATS_TEST_DIRNAME 設定時のみ有効）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PLUGINS_TWL_DIR: テスト環境（BATS_TEST_DIRNAME が設定されている場合）のみオーバーライドを許可。
# 本番 hook 実行時は SCRIPT_DIR 起点の固定パスを使用し Path Traversal を防止する。
if [[ -n "${BATS_TEST_DIRNAME:-}" && -n "${PLUGINS_TWL_DIR:-}" ]]; then
  # bats テスト環境: PLUGINS_TWL_DIR オーバーライドを許可
  PLUGINS_TWL_DIR="${PLUGINS_TWL_DIR}"
else
  # 本番環境: SCRIPT_DIR から固定パスで解決
  PLUGINS_TWL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# --- Step 1: コマンド解決 ---
# TOOL_INPUT_command 環境変数（Claude Code が PreToolUse で注入）を優先。
# 未設定の場合は stdin から JSON を試みる（フォールバック）。
CMD="${TOOL_INPUT_command:-}"
if [[ -z "$CMD" ]]; then
  # stdin から JSON payload を読み取り、tool_input.command を抽出
  payload="$(cat 2>/dev/null || echo "")"
  if [[ -n "$payload" ]] && echo "$payload" | jq empty 2>/dev/null; then
    CMD=$(echo "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
  fi
fi

# コマンドが取得できなかった場合はスキップ（no-op）
if [[ -z "$CMD" ]]; then
  exit 0
fi

# --- Step 2: git commit 以外はスキップ ---
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# --- Step 3: バイパスチェック ---
# 環境変数 TWL_SKIP_COMMIT_GATE=1 のみでバイパス。
# コマンド文字列内の文字列マッチは commit メッセージによる意図せぬバイパスを防ぐため行わない。
if [[ "${TWL_SKIP_COMMIT_GATE:-}" == "1" ]]; then
  echo "[WARN] TWL_SKIP_COMMIT_GATE: commit gate bypassed" >&2
  exit 0
fi

# --- Step 4: deps.yaml 存在チェック ---
if [[ ! -f "${PLUGINS_TWL_DIR}/deps.yaml" ]]; then
  # deps.yaml が見つからない（プロジェクトルート外など）→ スキップ
  exit 0
fi

# --- Step 5: twl が存在するか確認 ---
if ! command -v twl >/dev/null 2>&1; then
  # twl コマンドが見つからない → スキップ（グレースフル）
  exit 0
fi

# --- Step 6: twl --validate 実行 ---
cd "$PLUGINS_TWL_DIR"
if twl --validate; then
  exit 0
else
  exit 2
fi
