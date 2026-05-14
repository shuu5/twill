#!/usr/bin/env bats
# EXP-001: PreToolUse hook matcher 単数 schema 受理
#
# 検証内容 (公式 docs https://code.claude.com/docs/en/hooks):
#   - hook config の matcher field は単数形 "matcher" (string) のみ受理
#   - 複数 tool 列挙は pipe 区切り string ("Bash|Edit")、配列 "matchers": [...] は非サポート
#   - twill 内既存 hook config (.claude/settings.json) は全件 matcher 単数形使用
#
# 検証手法 (bats unit, schema 静的 check):
#   - fixture: 単数 / 複数 配列 / pipe 区切り の 3 種 settings.json を生成
#   - jq で field 名を assertion (実機 hook fire は smoke 必要)
#
# 制約: bats unit では Claude Code runtime 動作確認不可。実機 fire 検証は smoke test (Phase D 以降) で別途行う。

load '../common'

setup() {
    exp_common_setup
    SETTINGS_REAL="${REPO_ROOT}/.claude/settings.json"
}

teardown() {
    exp_common_teardown
}

@test "matcher-singular: 単数 matcher fixture (matcher: \"Bash\") の field 名は matcher" {
    local fix="${SANDBOX}/singular.json"
    cat > "$fix" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "echo ok" }] }
    ]
  }
}
EOF
    local name
    name=$(jq -r '.hooks.PreToolUse[0] | keys[]' "$fix" | sort | head -1)
    [ "$name" = "hooks" ] || [ "$name" = "matcher" ]
    # Wrap jq -e in `run` so the test fails when the assertion fails
    # (a bare `jq -e ...` mid-test is silently ignored — only the final
    #  command's exit code is the test's exit code).
    run jq -e '.hooks.PreToolUse[0] | has("matcher") and (has("matchers") | not)' "$fix"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$fix")" = "Bash" ]
}

@test "matcher-singular: pipe 区切り matcher (\"Bash|Edit\") は単数 field で複数 tool 受理" {
    local fix="${SANDBOX}/pipe.json"
    cat > "$fix" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash|Edit", "hooks": [{ "type": "command", "command": "echo ok" }] }
    ]
  }
}
EOF
    [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$fix")" = "Bash|Edit" ]
    jq -e '.hooks.PreToolUse[0].matcher | contains("|")' "$fix"
}

@test "matcher-singular: 複数形 matchers 配列は schema-invalid (公式 docs 仕様)" {
    local fix="${SANDBOX}/plural.json"
    cat > "$fix" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matchers": ["Bash", "Edit"], "hooks": [{ "type": "command", "command": "echo ok" }] }
    ]
  }
}
EOF
    # field "matchers" (plural array) is the **invalid** form per spec.
    # Confirm fixture distinguishes from singular form for downstream tooling.
    run jq -e '.hooks.PreToolUse[0] | has("matchers") and (has("matcher") | not)' "$fix"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hooks.PreToolUse[0].matchers | length' "$fix")" = "2" ]
}

@test "matcher-singular: twill 内 .claude/settings.json は全 PreToolUse entry が単数 matcher を使う" {
    [ -f "$SETTINGS_REAL" ] || skip "settings.json not found at $SETTINGS_REAL"
    python3 -c "
import json, sys
with open('$SETTINGS_REAL') as f:
    cfg = json.load(f)
hooks = cfg.get('hooks', {}).get('PreToolUse', [])
errs = []
for i, ent in enumerate(hooks):
    if 'matchers' in ent:
        errs.append(f'PreToolUse[{i}]: uses plural matchers (schema-invalid)')
    if 'matcher' not in ent:
        errs.append(f'PreToolUse[{i}]: missing matcher field')
if errs:
    print('\n'.join(errs)); sys.exit(1)
print(f'verified: {len(hooks)} PreToolUse entries all use singular matcher field')
sys.exit(0)
"
}

@test "matcher-singular: registry.yaml hooks-monitors.hooks entry も matcher 単数 (互換性確保)" {
    local registry="${REPO_ROOT}/plugins/twl/registry.yaml"
    [ -f "$registry" ] || skip "registry.yaml not found"
    python3 -c "
import yaml, sys
with open('$registry') as f:
    data = yaml.safe_load(f)
hooks = data.get('hooks-monitors', {}).get('hooks', [])
errs = []
for ent in hooks:
    if not isinstance(ent, dict):
        continue
    if 'matchers' in ent:
        errs.append(f\"{ent.get('name', '?')}: uses plural matchers field (schema-invalid)\")
if errs:
    print('\n'.join(errs)); sys.exit(1)
sys.exit(0)
"
}
