#!/usr/bin/env bats
# EXP-002: PreToolUse hook exit code 0/1/2 semantics
#
# 検証内容 (公式 docs https://code.claude.com/docs/en/hooks):
#   - exit 0: success — stdout JSON parse (permissionDecision に従う)。JSON 不在なら allow
#   - exit 2: blocking error — tool call は deny、stderr が Claude に表示
#   - exit 1 / 3+: non-blocking error — tool call は allow されるが error 記録
#
# 検証手法 (bats unit):
#   - 既存 hook script: `pre-tool-use-deps-yaml-guard.sh` (exit 2 直接 deny pattern)
#   - 既存 hook script: `pre-tool-use-worktree-boundary.sh` (exit 0 + JSON pattern)
#   - mock hook script: exit 0/1/2 を直接返す stub で挙動を網羅

load '../common'

setup() {
    exp_common_setup
    HOOK_WORKTREE_GUARD="${REPO_ROOT}/plugins/twl/scripts/hooks/pre-tool-use-worktree-boundary.sh"
    HOOK_DEPS_GUARD="${REPO_ROOT}/plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh"
}

teardown() {
    exp_common_teardown
}

_make_mock_hook() {
    # _make_mock_hook <name> <exit_code> [<stdout_content>]
    local name="$1"
    local exit_code="$2"
    local stdout="${3:-}"
    local hook="${SANDBOX}/${name}.sh"
    cat > "$hook" <<EOF
#!/usr/bin/env bash
set -uo pipefail
cat > /dev/null  # consume stdin
EOF
    if [[ -n "$stdout" ]]; then
        echo "echo '${stdout}'" >> "$hook"
    fi
    echo "exit ${exit_code}" >> "$hook"
    chmod +x "$hook"
    printf '%s\n' "$hook"
}

@test "exit-code: mock hook exit 0 + 空 stdout は success" {
    local hook
    hook=$(_make_mock_hook "allow" 0 "")
    echo '{}' | "$hook"
    [ "$?" -eq 0 ]
}

@test "exit-code: mock hook exit 0 + JSON allow stdout は parse 可能" {
    local hook
    hook=$(_make_mock_hook "allow-json" 0 '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}')
    local out
    out=$(echo '{}' | "$hook")
    echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "allow"'
}

@test "exit-code: mock hook exit 2 は blocking deny (公式仕様)" {
    local hook
    hook=$(_make_mock_hook "deny-blocking" 2 "")
    run bash -c "echo '{}' | '$hook'"
    [ "$status" -eq 2 ]
}

@test "exit-code: mock hook exit 1 は non-blocking (allow with log)" {
    local hook
    hook=$(_make_mock_hook "nonblock-err" 1 "")
    run bash -c "echo '{}' | '$hook'"
    [ "$status" -eq 1 ]
}

@test "exit-code: 既存 pre-tool-use-deps-yaml-guard.sh は exit 2 で deny (deps.yaml 不正 YAML 時)" {
    [ -x "$HOOK_DEPS_GUARD" ] || skip "deps-yaml-guard hook not present"
    # invalid YAML を Write tool で書こうとする payload (basename: deps.yaml)
    local payload
    payload=$(jq -nc '{
      tool_name: "Write",
      tool_input: { file_path: "/tmp/some-path/deps.yaml", content: "key: : invalid yaml" }
    }')
    run bash -c "printf '%s' '$payload' | bash '$HOOK_DEPS_GUARD'"
    [ "$status" -eq 2 ]
}

@test "exit-code: 既存 pre-tool-use-worktree-boundary.sh は AUTOPILOT_DIR 未設定で no-op (exit 0)" {
    [ -x "$HOOK_WORKTREE_GUARD" ] || skip "worktree-boundary hook not present"
    local payload
    payload=$(jq -nc '{tool_name: "Edit", tool_input: {file_path: "/tmp/anywhere"}}')
    # ensure AUTOPILOT_DIR is unset
    run bash -c "unset AUTOPILOT_DIR; printf '%s' '$payload' | bash '$HOOK_WORKTREE_GUARD'"
    [ "$status" -eq 0 ]
}

@test "exit-code: hook stderr is captured separately from stdout (deny の理由表示用)" {
    local hook="${SANDBOX}/stderr-hook.sh"
    cat > "$hook" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo "tool denied: bad path" >&2
exit 2
EOF
    chmod +x "$hook"
    local stderr_file="${SANDBOX}/err.log"
    run bash -c "echo '{}' | '$hook' 2>'$stderr_file'"
    [ "$status" -eq 2 ]
    grep -q "tool denied: bad path" "$stderr_file"
}
