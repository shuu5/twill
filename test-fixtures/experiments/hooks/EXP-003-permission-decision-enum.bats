#!/usr/bin/env bats
# EXP-003: permissionDecision enum 受理
#
# 検証内容 (公式 docs https://code.claude.com/docs/en/hooks):
#   - permissionDecision: "allow" | "deny" | "ask" | "defer" の 4 値が正規 enum
#   - 旧 "approve" / "block" は古い enum (現行 schema では非サポート)
#   - hookSpecificOutput.hookEventName == "PreToolUse" が必須
#
# 検証手法 (bats unit):
#   - mock hook script に各 enum 値を埋め込んで JSON output を生成
#   - jq -e で schema validity を assertion
#   - 旧 enum (approve/block) を出力する mock も作って「JSON は valid だが enum value が旧式」を区別

load '../common'

setup() {
    exp_common_setup
}

teardown() {
    exp_common_teardown
}

_make_decision_hook() {
    # _make_decision_hook <decision_value>
    local decision="$1"
    local hook="${SANDBOX}/decision-${decision}.sh"
    cat > "$hook" <<EOF
#!/usr/bin/env bash
cat > /dev/null
cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "${decision}",
    "permissionDecisionReason": "EXP-003 test fixture (${decision})"
  }
}
JSON
exit 0
EOF
    chmod +x "$hook"
    printf '%s\n' "$hook"
}

@test "decision-enum: allow output は valid JSON で hookEventName == PreToolUse" {
    local hook out
    hook=$(_make_decision_hook "allow")
    out=$(echo '{}' | "$hook")
    # Wrap intermediate jq -e in `run` to ensure assertion failure trips the test
    run jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' <<<"$out"
    [ "$status" -eq 0 ]
    run jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<<"$out"
    [ "$status" -eq 0 ]
}

@test "decision-enum: deny output は valid JSON で permissionDecision == deny" {
    local hook out
    hook=$(_make_decision_hook "deny")
    out=$(echo '{}' | "$hook")
    echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "decision-enum: ask output は valid JSON" {
    local hook out
    hook=$(_make_decision_hook "ask")
    out=$(echo '{}' | "$hook")
    echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"'
}

@test "decision-enum: defer output は valid JSON" {
    local hook out
    hook=$(_make_decision_hook "defer")
    out=$(echo '{}' | "$hook")
    echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "defer"'
}

@test "decision-enum: 4 enum 値は canonical set {allow,deny,ask,defer} 内 (旧 approve/block を除外)" {
    local valid=("allow" "deny" "ask" "defer")
    local invalid=("approve" "block")
    local v
    for v in "${valid[@]}"; do
        local h
        h=$(_make_decision_hook "$v")
        echo '{}' | "$h" | jq -e --arg v "$v" '.hookSpecificOutput.permissionDecision == $v'
    done
    # invalid enum: JSON 自体は valid だが現行 schema 違反
    for v in "${invalid[@]}"; do
        local h
        h=$(_make_decision_hook "$v")
        local out
        out=$(echo '{}' | "$h")
        # JSON 構造は parse 可能
        echo "$out" | jq -e .  > /dev/null
        # しかし canonical set 外
        local got
        got=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision')
        [[ "$got" == "approve" || "$got" == "block" ]]
    done
}

@test "decision-enum: permissionDecisionReason field を含む output の parse" {
    local hook out
    hook=$(_make_decision_hook "deny")
    out=$(echo '{}' | "$hook")
    echo "$out" | jq -e '.hookSpecificOutput.permissionDecisionReason | type == "string"'
}

@test "decision-enum: registry.yaml hooks-monitors.hooks に decision_default field がある場合は enum 内" {
    local registry="${REPO_ROOT}/plugins/twl/registry.yaml"
    [ -f "$registry" ] || skip "registry.yaml not found"
    python3 -c "
import yaml, sys
with open('$registry') as f:
    data = yaml.safe_load(f)
hooks = data.get('hooks-monitors', {}).get('hooks', [])
valid_enum = {'allow', 'deny', 'ask', 'defer'}
errs = []
for ent in hooks:
    if not isinstance(ent, dict):
        continue
    dd = ent.get('decision_default')
    if dd is not None and dd not in valid_enum:
        errs.append(f\"{ent.get('name', '?')}: decision_default={dd!r} not in canonical enum {valid_enum}\")
if errs:
    print('\n'.join(errs)); sys.exit(1)
sys.exit(0)
"
}
