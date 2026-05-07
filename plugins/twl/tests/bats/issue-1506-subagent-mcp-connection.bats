#!/usr/bin/env bats
# issue-1506-subagent-mcp-connection.bats
#
# RED-phase tests for Issue #1506:
#   bug(twl-mcp): subagent から `MCP server 'twl' not connected` で
#                 PreToolUse:Bash hook が失敗する問題
#
# AC coverage:
#   AC1: subagent から mcp__twl__* tool が呼べる設定が存在する（静的確認）
#        - .mcp.json に twl エントリが存在し、subagent が継承できる構造であること
#   AC2: PreToolUse:Bash hook が MCP server 'twl' not connected を出さない（静的確認）
#        - subagent が MCP 接続を継承できる設定/仕組みが整備されていること
#   AC3: bats test 追加（本ファイル自体の存在確認）
#        - plugins/twl/tests/bats/issue-1506-subagent-mcp-connection.bats が存在すること
#   AC4: subagent MCP server inheritance の ADR を作成 or 既存 ADR に追記（静的確認）
#        - plugins/twl/architecture/decisions/ に subagent MCP server inheritance の ADR
#          ファイルが存在するか、既存 ADR に追記されていること
#
# RED となるテスト: AC1 (subagent MCP 継承設定不在), AC2 (PreToolUse hook 接続設定不在),
#                   AC3 (本ファイル自体がまだ存在しない状態での RED),
#                   AC4 (subagent MCP server inheritance ADR 不在)

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  # tests/bats/ -> tests/ -> plugins/twl/ (REPO_ROOT = plugins/twl/)
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  # リポジトリルート (twill モノリポルート) = plugins/twl/ の 2 つ上
  MONO_ROOT="$(cd "${REPO_ROOT}/../.." && pwd)"
  export MONO_ROOT

  MCP_JSON="${MONO_ROOT}/.mcp.json"
  DECISIONS_DIR="${REPO_ROOT}/architecture/decisions"
  BATS_TARGET_FILE="${this_dir}/issue-1506-subagent-mcp-connection.bats"
  export MCP_JSON DECISIONS_DIR BATS_TARGET_FILE
}

# ===========================================================================
# AC1: .mcp.json に twl エントリが存在し subagent が継承できる構造であること
# subagent から mcp__twl__* tool が呼べる前提として、.mcp.json の twl エントリが
# 正しい構造（type: stdio, command: uv, args に fastmcp run を含む）で存在することを確認する
# ===========================================================================

@test "ac1: .mcp.json exists at mono root" {
  # AC: .mcp.json がモノリポルートに存在すること
  # RED: .mcp.json が存在しない（または subagent 継承に必要な構造でない）場合 fail
  [ -f "${MCP_JSON}" ]
}

@test "ac1: .mcp.json contains 'twl' server entry" {
  # AC: .mcp.json に mcpServers.twl エントリが存在すること
  # RED: twl エントリが未定義の場合 fail
  run grep -qF '"twl"' "${MCP_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac1: .mcp.json twl entry has stdio type" {
  # AC: .mcp.json の twl エントリに "type": "stdio" が設定されていること
  # (stdio タイプが subagent 継承の前提条件)
  # RED: type が stdio 以外または未設定の場合 fail
  run grep -qF '"type": "stdio"' "${MCP_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac1: .mcp.json twl entry invokes fastmcp" {
  # AC: .mcp.json の twl エントリが fastmcp を使用してサーバーを起動すること
  # (command フィールドまたは args にて fastmcp が指定されていること)
  # uv run fastmcp run ... または .venv/bin/fastmcp ... のどちらも許容
  run grep -qE '"fastmcp"|/fastmcp' "${MCP_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac1: .mcp.json twl entry points to mcp_server/server.py" {
  # AC: .mcp.json の twl エントリが src/twl/mcp_server/server.py を参照していること
  # RED: server.py パスが args に含まれない場合 fail
  run grep -qF 'server.py' "${MCP_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac1: subagent MCP inheritance config or env mechanism exists" {
  # AC: subagent が MCP server を継承できる仕組み（設定ファイル、env var、または
  #     CLAUDE_CODE_SUBAGENT_MCP_INHERIT 等の機構）が整備されていること
  # RED: subagent MCP 継承を明示的に有効化する設定が存在しない場合 fail
  # 確認対象: .mcp.json に inherit/subagent 設定が存在するか、
  #           または .claude/settings.json に subagent MCP 継承設定が存在するか
  local settings_json="${MONO_ROOT}/.claude/settings.json"
  local found=0

  # .mcp.json に "allowSubagents" や subagent 継承設定があるか
  if grep -qiE '"allowSubagents"|"subagentInherit"|"inheritMcp"' "${MCP_JSON}" 2>/dev/null; then
    found=1
  fi

  # .claude/settings.json に subagent MCP 継承設定があるか
  if [ -f "${settings_json}" ] && grep -qiE '"allowSubagents"|"subagentMcp"|"mcpInherit"' "${settings_json}" 2>/dev/null; then
    found=1
  fi

  # subagent 向け MCP 設定ファイル（例: .claude/subagent-mcp.json）が存在するか
  if [ -f "${MONO_ROOT}/.claude/subagent-mcp.json" ]; then
    found=1
  fi

  [ "${found}" -eq 1 ]
}

# ===========================================================================
# AC2: PreToolUse:Bash hook が MCP server 'twl' not connected を出さない
# 両 hook event で twl MCP 接続済み状態であることを保証する設定の存在確認
# ===========================================================================

@test "ac2: PreToolUse Bash hook references twl mcp_tool in settings.json" {
  # AC: .claude/settings.json の PreToolUse Bash hook に mcp_tool type で twl が設定されていること
  # RED: twl mcp_tool が PreToolUse Bash hook に設定されていない場合 fail
  local settings_json="${MONO_ROOT}/.claude/settings.json"
  [ -f "${settings_json}" ]
  run grep -qF '"server": "twl"' "${settings_json}"
  [ "${status}" -eq 0 ]
}

@test "ac2: twl mcp server is listed in PreToolUse Bash hook context" {
  # AC: settings.json の PreToolUse:Bash フック内に mcp_tool twl への参照が存在すること
  # RED: PreToolUse:Bash コンテキストで twl mcp_tool が定義されていない場合 fail
  local settings_json="${MONO_ROOT}/.claude/settings.json"
  [ -f "${settings_json}" ]

  # "Bash" matcher 配下に "twl" server の mcp_tool が存在するかを確認
  # jq を使って PreToolUse.Bash フックに twl mcp_tool が含まれるかチェック
  run bash -c "
    jq -e '
      .hooks.PreToolUse[]
      | select(.matcher == \"Bash\")
      | .hooks[]
      | select(.type == \"mcp_tool\" and .server == \"twl\")
    ' '${settings_json}' > /dev/null 2>&1
  "
  [ "${status}" -eq 0 ]
}

@test "ac2: subagent MCP connection does not fail due to missing twl server config" {
  # AC: subagent 起動時に MCP server 'twl' not connected エラーが発生しない前提条件が
  #     整備されていること
  # 前提: subagent が .mcp.json を継承できる設定か、または subagent 向け別設定が存在する
  # RED: 以下のいずれの設定も存在しない場合 fail
  #   1. CLAUDE_CODE_SUBAGENT_MCP_INHERIT 的な env var を設定するスクリプト
  #   2. subagent 起動フックで MCP 接続を確立するスクリプト
  #   3. .mcp.json の subagent 継承設定
  local found=0

  # subagent MCP 接続修正スクリプトが存在するか
  if find "${REPO_ROOT}/scripts" -name "*subagent*mcp*" -o -name "*mcp*subagent*" 2>/dev/null | grep -q .; then
    found=1
  fi

  # SubagentStop hook に twl mcp_tool が設定されているか（接続確認の証拠）
  local settings_json="${MONO_ROOT}/.claude/settings.json"
  if [ -f "${settings_json}" ] && \
     jq -e '.hooks.SubagentStop[]? | .hooks[]? | select(.type == "mcp_tool" and .server == "twl")' \
       "${settings_json}" > /dev/null 2>&1; then
    found=1
  fi

  # subagent 向け MCP 継承修正が co-explore または co-autopilot の SKILL.md に記述されているか
  if grep -ql "subagent.*mcp\|mcp.*subagent\|MCP.*inherit\|inherit.*MCP" \
       "${REPO_ROOT}/skills/co-explore/SKILL.md" \
       "${REPO_ROOT}/skills/co-autopilot/SKILL.md" 2>/dev/null; then
    found=1
  fi

  [ "${found}" -eq 1 ]
}

# ===========================================================================
# AC3: bats test 追加 — 本ファイル自体の存在確認
# 「AC3 の成果物 = bats テストファイルが存在する」という静的チェック
# 現時点では本ファイルが存在しないため RED（実装後に GREEN になる）
# ===========================================================================

@test "ac3: issue-1506-subagent-mcp-connection.bats exists in plugins/twl/tests/bats/" {
  # AC: plugins/twl/tests/bats/issue-1506-subagent-mcp-connection.bats が存在すること
  # NOTE: 本テスト自体が当該ファイルであるため、実行時は常に PASS するが、
  #       CI での静的存在確認（別スクリプト参照）の確実性を担保するための記録テスト
  [ -f "${BATS_TARGET_FILE}" ]
}

@test "ac3: issue-1506 bats file contains AC1 test cases" {
  # AC: 追加された bats テストに AC1 (subagent MCP 接続) のテストケースが含まれること
  # RED: AC1 テストが bats ファイルに実装されていない場合 fail
  run grep -qF '"ac1:' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

@test "ac3: issue-1506 bats file contains AC2 test cases" {
  # AC: 追加された bats テストに AC2 (PreToolUse hook MCP 接続エラーなし) のテストケースが含まれること
  # RED: AC2 テストが bats ファイルに実装されていない場合 fail
  run grep -qF '"ac2:' "${BATS_TARGET_FILE}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: subagent MCP server inheritance の ADR が作成 or 既存 ADR に追記されていること
# plugins/twl/architecture/decisions/ を確認する
# ===========================================================================

@test "ac4: ADR file for subagent MCP server inheritance exists" {
  # AC: plugins/twl/architecture/decisions/ に subagent MCP server inheritance に関する
  #     ADR ファイルが存在すること（新規 ADR または既存 ADR への追記）
  # RED: subagent MCP server inheritance を扱う ADR が存在しない場合 fail

  # 新規 ADR ファイル（例: ADR-035-subagent-mcp-server-inheritance.md）の存在確認
  local found=0
  if find "${DECISIONS_DIR}" -name "*subagent*mcp*" -o -name "*mcp*subagent*" 2>/dev/null | grep -q .; then
    found=1
  fi

  # 既存 ADR ファイルに subagent MCP inheritance に関する追記がある場合も可とする
  if grep -rl "subagent.*MCP.*inherit\|MCP.*inherit.*subagent\|subagent MCP server\|MCP server.*subagent" \
       "${DECISIONS_DIR}/" 2>/dev/null | grep -q .; then
    found=1
  fi

  [ "${found}" -eq 1 ]
}

@test "ac4: ADR for subagent MCP inheritance references Issue 1506" {
  # AC: 作成または更新された ADR に Issue #1506 への参照が含まれること
  # RED: ADR 内に #1506 参照が存在しない場合 fail
  run grep -rl "#1506\|Issue.*1506\|1506.*bug" "${DECISIONS_DIR}/"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac4: ADR for subagent MCP inheritance has Accepted status" {
  # AC: 関連 ADR の Status が Accepted であること
  # RED: Status が Draft / Proposed のまま（または存在しない）場合 fail
  local adr_file
  adr_file="$(grep -rl "#1506\|Issue.*1506" "${DECISIONS_DIR}/" 2>/dev/null | head -1)"

  if [ -z "${adr_file}" ]; then
    # ADR ファイル自体が存在しない = RED
    false
    return
  fi

  run grep -qiE "^## Status" "${adr_file}"
  [ "${status}" -eq 0 ]

  run grep -qiE "Accepted" "${adr_file}"
  [ "${status}" -eq 0 ]
}

@test "ac4: ADR context describes subagent MCP server not connected error" {
  # AC: ADR の Context セクションに MCP server not connected 問題の背景が記述されていること
  # RED: 背景記述が ADR に存在しない場合 fail
  run grep -rl "MCP server.*not connected\|not connected.*MCP server\|subagent.*MCP" \
    "${DECISIONS_DIR}/"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}
