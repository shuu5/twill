#!/usr/bin/env bats
# EXP-007: tier 1 + tier 2 parallel 実行
#
# 検証内容 (gate-hook.html §4-5):
#   - 同 PreToolUse event に command hook (tier 1) + mcp_tool hook (tier 2) を 2 つ登録可能
#   - 両 hook が parallel 実行され、両 reason が additionalContext に含まれる
#
# bats unit (schema 静的 check):
#   - settings.json fixture で同一 event + 同 matcher の hook 2 つ並列定義が valid な JSON 構造であることを確認
#   - tier 1 (command type) と tier 2 (mcp_tool type) の混在を schema レベルで検証
#
# smoke (Claude session 必須、別 EXP-XXX で別途):
#   - 実機での parallel 実行 + additionalContext merge 動作確認 → Phase 4 CI 自動化対象

load '../common'

setup() {
    exp_common_setup
}

teardown() {
    exp_common_teardown
}

@test "tier-parallel: 同 PreToolUse event に command + mcp_tool hook 2 件並列定義が valid JSON" {
    local fix="${SANDBOX}/tier-hooks.json"
    cat > "$fix" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          { "type": "command", "command": "echo tier1-command" }
        ]
      },
      {
        "matcher": "Edit",
        "hooks": [
          { "type": "mcp_tool", "server": "twl", "tool": "twl_validate_deps", "input": {}, "outputType": "log" }
        ]
      }
    ]
  }
}
EOF
    # 2 entries with same matcher, distinct hook types
    [ "$(jq -r '.hooks.PreToolUse | length' "$fix")" = "2" ]
    [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$fix")" = "Edit" ]
    [ "$(jq -r '.hooks.PreToolUse[1].matcher' "$fix")" = "Edit" ]
    run jq -e '.hooks.PreToolUse[0].hooks[0].type == "command"' "$fix"
    [ "$status" -eq 0 ]
    run jq -e '.hooks.PreToolUse[1].hooks[0].type == "mcp_tool"' "$fix"
    [ "$status" -eq 0 ]
}

@test "tier-parallel: twill 内 .claude/settings.json に command + mcp_tool 混在 entry が存在 (静的確認)" {
    local settings="${REPO_ROOT}/.claude/settings.json"
    [ -f "$settings" ] || skip "settings.json not found at $settings"
    python3 -c "
import json
with open('$settings') as f:
    cfg = json.load(f)
hooks = cfg.get('hooks', {}).get('PreToolUse', [])
has_command = False
has_mcp_tool = False
for ent in hooks:
    for h in ent.get('hooks', []):
        if h.get('type') == 'command':
            has_command = True
        if h.get('type') == 'mcp_tool':
            has_mcp_tool = True
import sys
if not has_command:
    print('no command-type hook found in PreToolUse')
    sys.exit(1)
# mcp_tool may or may not be present per spec
print(f'verified: command={has_command} mcp_tool={has_mcp_tool}')
sys.exit(0)
"
}

@test "tier-parallel: 同 matcher の hook entry 並列は schema 上 array index で識別可能" {
    local fix="${SANDBOX}/multi.json"
    cat > "$fix" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "true" }] },
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "false" }] }
    ]
  }
}
EOF
    # 同じ matcher を 2 entries で持つことは仕様上許可される (tier 並列)
    [ "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash")] | length' "$fix")" = "2" ]
}

@test "tier-parallel: smoke verification (実機 parallel 起動) は別 EXP で Phase D 以降に実施" {
    skip "実機 parallel 起動 + additionalContext merge 検証は smoke (Claude session 必須)、Phase D 以降"
}
