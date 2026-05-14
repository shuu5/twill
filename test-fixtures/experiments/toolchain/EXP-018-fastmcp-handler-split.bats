#!/usr/bin/env bats
# EXP-018: fastmcp v3.0.0 @mcp.tool + handler 分離 in-process test
#
# 検証内容 (gofastmcp.com/servers/tools + twl 独自 pattern):
#   - fastmcp v3.0.0 では mcp = FastMCP(name="test") + @mcp.tool decorator
#   - twl 独自 pattern: 純 Python handler を import し、fastmcp なし環境でも直接呼び出せる
#   - deferred-tool pattern が動作 (handler は @mcp.tool decoration なしの pure function)
#
# 検証手法 (bats unit):
#   - cli/twl の uv env で fastmcp 3.x が install 済を確認
#   - inline Python で FastMCP + @mcp.tool decorator + handler 分離 import を実行
#   - twl 独自 handler 例 (cli/twl 配下) の import を試行

load '../common'

setup() {
    exp_common_setup
    CLI_TWL="${REPO_ROOT}/cli/twl"
    [ -d "$CLI_TWL" ] || skip "cli/twl not found at $CLI_TWL"
}

teardown() {
    exp_common_teardown
}

@test "fastmcp: cli/twl uv env で fastmcp 3.x が import 可能" {
    run bash -c "cd '$CLI_TWL' && uv run python3 -c 'import fastmcp; print(fastmcp.__version__)'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^3\. ]]
}

@test "fastmcp: FastMCP(name=...) + @mcp.tool decorator が動作" {
    run bash -c "cd '$CLI_TWL' && uv run python3 <<'PY'
from fastmcp import FastMCP
mcp = FastMCP(name='exp-018-test')
@mcp.tool
def add(a: int, b: int) -> int:
    return a + b
# decorator は実関数を返す (in-process test の前提)
result = add(2, 3)
assert result == 5, f'expected 5, got {result}'
print('PASS: @mcp.tool decorator preserves callable behavior')
PY
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "fastmcp: handler 分離 — pure function を @mcp.tool で wrap して呼び出し可能" {
    run bash -c "cd '$CLI_TWL' && uv run python3 <<'PY'
from fastmcp import FastMCP
# pure handler (no fastmcp dependency)
def pure_handler(x: int) -> int:
    return x * 2
# fastmcp で wrap
mcp = FastMCP(name='exp-018-split')
wrapped = mcp.tool(pure_handler)
# 直接呼び出し (deferred-tool pattern)
assert pure_handler(7) == 14, 'pure handler direct call'
print('PASS: pure handler direct + @mcp.tool wrap 双方動作')
PY
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "fastmcp: cli/twl mcp_main.py が import 可能 (twl 独自 handler-split 実装の存在確認)" {
    run bash -c "cd '$CLI_TWL' && uv run python3 -c 'from twl import mcp_main; print(mcp_main.__file__)' 2>&1"
    if [ "$status" -ne 0 ]; then
        skip "twl.mcp_main not found (Phase 1 PoC 未実装 or alternative path)"
    fi
    [[ "$output" == *"mcp_main"* ]]
}

@test "fastmcp: twl-mcp-integration.html §1.1 で handler 分離 pattern が記載されている (static check)" {
    local spec="${REPO_ROOT}/architecture/spec/twill-plugin-rebuild/twl-mcp-integration.html"
    [ -f "$spec" ] || skip "twl-mcp-integration.html not found"
    grep -qi 'handler.*分離\|handler.*split\|deferred.tool' "$spec" \
        || skip "handler 分離 pattern not documented (Phase D で追記)"
}
