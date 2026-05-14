#!/usr/bin/env bats
# EXP-028: pre-tool-use-spec-write-boundary.sh caller boundary
#
# 検証内容 (tool-architecture.html §3.4):
#   architecture/spec/* 配下への Edit/Write/NotebookEdit を caller 識別 (TWL_TOOL_CONTEXT)
#   ベースで allow/deny。
#     - unset             → user manual edit (allow)
#     - tool-architect    → tool-architect skill 経由 (allow)
#     - その他            → deny (JSON output、permissionDecision: deny)
#
# caller 識別 logic 確定 (本 Phase C で確定): TWL_TOOL_CONTEXT env var が canonical SSoT。
#
# 検証手法 (bats unit):
#   - stdin JSON injection で hook を直接呼ぶ pattern (既存 pre-tool-use-*.bats と同じ)

load '../common'

setup() {
    exp_common_setup
    HOOK="${REPO_ROOT}/plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh"
}

teardown() {
    exp_common_teardown
}

_make_payload() {
    # _make_payload <tool_name> <file_path>
    jq -nc --arg t "$1" --arg p "$2" '{tool_name: $t, tool_input: {file_path: $p}}'
}

_run_hook() {
    # _run_hook <payload> [<env_caller>]
    local payload="$1"
    local caller="${2:-}"
    if [[ -n "$caller" ]]; then
        TWL_TOOL_CONTEXT="$caller" bash "$HOOK" <<<"$payload"
    else
        unset TWL_TOOL_CONTEXT
        bash "$HOOK" <<<"$payload"
    fi
}

@test "spec-write-boundary: hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "spec-write-boundary: architecture/spec/ 配下 + TWL_TOOL_CONTEXT unset → allow (exit 0、空 output)" {
    local payload
    payload=$(_make_payload "Edit" "/repo/architecture/spec/twill-plugin-rebuild/foo.html")
    run _run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "spec-write-boundary: architecture/spec/ 配下 + TWL_TOOL_CONTEXT=tool-architect → allow" {
    local payload
    payload=$(_make_payload "Write" "/repo/architecture/spec/twill-plugin-rebuild/bar.html")
    run _run_hook "$payload" "tool-architect"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "spec-write-boundary: architecture/spec/ 配下 + TWL_TOOL_CONTEXT=phaser-impl → deny JSON" {
    local payload deny_out
    payload=$(_make_payload "Edit" "/repo/architecture/spec/twill-plugin-rebuild/foo.html")
    deny_out=$(_run_hook "$payload" "phaser-impl")
    # Pin deny_out so consecutive `run jq` invocations don't clobber the
    # captured JSON via `$output` overwriting.
    run jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$deny_out"
    [ "$status" -eq 0 ]
    run jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' <<<"$deny_out"
    [ "$status" -eq 0 ]
    run jq -e '.hookSpecificOutput.permissionDecisionReason | contains("tool-architect")' <<<"$deny_out"
    [ "$status" -eq 0 ]
}

@test "spec-write-boundary: architecture/spec/ 配下 + TWL_TOOL_CONTEXT=tool-project → deny JSON" {
    local payload deny_out
    payload=$(_make_payload "Edit" "/repo/architecture/spec/twill-plugin-rebuild/foo.html")
    deny_out=$(_run_hook "$payload" "tool-project")
    run jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$deny_out"
    [ "$status" -eq 0 ]
}

@test "spec-write-boundary: architecture/spec 外 path は no-op (path boundary)" {
    local payload
    payload=$(_make_payload "Edit" "/repo/plugins/twl/SKILL.md")
    run _run_hook "$payload" "phaser-impl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "spec-write-boundary: Bash tool は no-op (Edit/Write/NotebookEdit のみ matcher)" {
    local payload
    payload=$(jq -nc '{tool_name: "Bash", tool_input: {command: "rm architecture/spec/foo.html"}}')
    run _run_hook "$payload" "phaser-impl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "spec-write-boundary: NotebookEdit + spec path + deny caller → deny JSON" {
    local payload deny_out
    payload=$(_make_payload "NotebookEdit" "/repo/architecture/spec/twill-plugin-rebuild/foo.html")
    deny_out=$(_run_hook "$payload" "worker-impl")
    run jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$deny_out"
    [ "$status" -eq 0 ]
}

@test "spec-write-boundary: 不正 JSON payload は no-op (悪い input を block しない)" {
    run bash "$HOOK" <<<"not a json"
    [ "$status" -eq 0 ]
}

@test "spec-write-boundary: file_path 不在 payload は no-op" {
    local payload
    payload=$(jq -nc '{tool_name: "Edit", tool_input: {old_string: "x", new_string: "y"}}')
    run _run_hook "$payload" "phaser-impl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
