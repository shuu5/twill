#!/usr/bin/env bats
# deps-yaml-mcp-shadow.bats
#
# RED テストスタブ (Issue #1225)
#
# AC-1:  .claude/settings.json に PreToolUse mcp_tool hook を追加
# AC-V1: PR diff で .claude/settings.json への PreToolUse mcp_tool hook 追加 (1 entry) が含まれる
# AC-V2: 既存 pre-tool-use-deps-yaml-guard.sh の bytes が不変（削除・改変防止）
# AC-V3: bats 5 サンプル全 PASS (mcp-shadow-compare.bats)
#
# 全テストは実装前に fail (RED) する。
#

load '../helpers/common'

SETTINGS_JSON=""
GUARD_SH=""
MCP_COMPARE_BATS=""
COMPARE_SH=""

setup() {
  common_setup

  # プロジェクトルートからの絶対パスを設定
  local git_root
  git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"

  SETTINGS_JSON="${git_root}/.claude/settings.json"
  GUARD_SH="${git_root}/plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh"
  MCP_COMPARE_BATS="${git_root}/plugins/twl/tests/bats/scripts/mcp-shadow-compare.bats"
  COMPARE_SH="${git_root}/plugins/twl/scripts/mcp-shadow-compare.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-1: .claude/settings.json に PreToolUse mcp_tool hook 追加
# WHEN settings.json を読み込む
# THEN PreToolUse の hooks 配列に mcp_tool matcher が 1 エントリ存在する
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC1: settings.json に PreToolUse mcp_tool hook が存在する" {
  # Edit|Write matcher 配下に type=mcp_tool, tool=twl_validate_deps のエントリが存在すること
  local count
  count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Edit|Write") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_deps")] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

@test "AC1: mcp_tool hook が正しい server と tool を参照する" {
  # server=twl, tool=twl_validate_deps であること
  local server tool
  server=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Edit|Write") | .hooks[]? | select(.type == "mcp_tool")] | .[0].server // empty' "$SETTINGS_JSON")
  tool=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Edit|Write") | .hooks[]? | select(.type == "mcp_tool")] | .[0].tool // empty' "$SETTINGS_JSON")
  [[ "$server" == "twl" ]]
  [[ "$tool" == "twl_validate_deps" ]]
}

# ---------------------------------------------------------------------------
# AC-V1: PR diff で settings.json への mcp_tool hook 追加 (1 entry) を機械検証
# WHEN git diff origin/main の settings.json diff を確認する
# THEN "mcp_tool" という文字列が diff に含まれる
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC-V1: git diff で settings.json に mcp_tool の追加が含まれる" {
  # git root から .claude/settings.json の diff を取得
  local git_root diff_output
  git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
  diff_output=$(git -C "$git_root" diff origin/main -- .claude/settings.json 2>/dev/null || true)
  [[ "$diff_output" == *"mcp_tool"* ]]
}

# ---------------------------------------------------------------------------
# AC-V2: 既存 pre-tool-use-deps-yaml-guard.sh の bytes が不変
# WHEN 現在の guard スクリプトのバイト数を測る
# THEN origin/main の同ファイルと同一バイト数（削除・改変なし）
# GREEN: 既存ファイルが保持されている限り pass する（regression guard）
# ---------------------------------------------------------------------------

@test "AC-V2: pre-tool-use-deps-yaml-guard.sh が存在する（削除されていない）" {
  # このテストは実装前後で GREEN を維持することが目的（regression guard）
  [ -f "$GUARD_SH" ]
}

@test "AC-V2: pre-tool-use-deps-yaml-guard.sh のバイト数が origin/main と一致する" {
  # git diff に guard スクリプトへの変更がないことを確認
  local guard_rel="plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh"
  local git_root
  git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
  local diff_output
  diff_output=$(git -C "$git_root" diff origin/main -- "$guard_rel" 2>/dev/null || true)
  # diff が空 = 変更なし
  [ -z "$diff_output" ]
}

# ---------------------------------------------------------------------------
# AC-V3: mcp-shadow-compare.bats が存在し bats で実行できること
# WHEN bats plugins/twl/tests/bats/scripts/mcp-shadow-compare.bats を実行する
# THEN 5 テスト全て PASS する
# RED: mcp-shadow-compare.bats が未作成なら fail する
# ---------------------------------------------------------------------------

@test "AC-V3: mcp-shadow-compare.bats ファイルが存在する" {
  # RED: ファイル未作成なら fail
  [ -f "$MCP_COMPARE_BATS" ]
}

@test "AC-V3: mcp-shadow-compare.bats を bats で実行すると全 PASS" {
  # RED: ファイル未作成 or テスト fail なら fail
  [ -f "$MCP_COMPARE_BATS" ] || skip "mcp-shadow-compare.bats が未作成のため skip"
  run bats "$MCP_COMPARE_BATS"
  [ "$status" -eq 0 ]
}
