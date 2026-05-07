#!/usr/bin/env bats
# ac-scaffold-tests-1535.bats
#
# Issue #1535: meta-bug(autopilot): Wave 70 AC4 false claim + Wave 71 test scaffold のみ再発
# lesson 19 構造化 fix が機能していない
#
# RED: 実装前は全テスト fail
# GREEN: 実装後に PASS

load 'helpers/common'

SCRIPTS_DIR=""
AGENTS_DIR=""
TOOLS_PY=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
  AGENTS_DIR="${REPO_ROOT}/agents"
  TOOLS_PY="${REPO_ROOT}/../../cli/twl/src/twl/mcp_server/tools.py"
  # plugins/twl/tests/bats から見た相対パスで解決
  local bats_dir
  bats_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  PLUGIN_ROOT="$(cd "${tests_dir}/.." && pwd)"
  # cli/twl は plugins/twl の兄弟ディレクトリではなく、monorepo root 直下
  REPO_GIT_ROOT="$(cd "${PLUGIN_ROOT}/.." && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  TOOLS_PY="${REPO_GIT_ROOT}/cli/twl/src/twl/mcp_server/tools.py"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: specialist-audit.sh に "test scaffold only" HARD FAIL を実装
#
# Worker PR の changed_files が test 系のみ (cli/twl/tests/、plugins/twl/tests/) で
# src/ への変更がない場合、specialist-audit.sh が STATUS=FAIL を返す。
#
# RED: 現在 specialist-audit.sh に "test scaffold only" 検出ロジックが存在しない
# GREEN: ロジック追加後 PASS
# ===========================================================================

@test "ac1a: specialist-audit.sh に 'test scaffold only' 検出ロジックが存在する" {
  # AC: test 系ファイルのみ変更の PR を検出するキーワードが specialist-audit.sh に存在する
  # RED: 現在 specialist-audit.sh に test-scaffold-only / scaffold only ロジックが存在しない
  run bash -c "grep -qE \
    'test.scaffold.only|scaffold.only|test[_-]only|RED.only|red.only.detector|changed_files.*test' \
    \"${SCRIPTS_DIR}/specialist-audit.sh\""
  assert_success
}

@test "ac1b: specialist-audit.sh に test-only PR の HARD FAIL パスが存在する" {
  # AC: test 系のみ変更の PR に対して STATUS=FAIL を返す分岐が存在する
  # RED: 現在 HARD FAIL パスが未実装のため grep fail
  run bash -c "grep -qE \
    'TEST_ONLY.*FAIL|FAIL.*test.only|test.scaffold.*FAIL|FAIL.*scaffold|test_only_fail|scaffold_only' \
    \"${SCRIPTS_DIR}/specialist-audit.sh\""
  assert_success
}

@test "ac1c: specialist-audit.sh が --changed-files オプションまたは同等の引数を受け付ける" {
  # AC: changed_files リストを specialist-audit.sh に渡せるインターフェースが存在する
  # RED: 現在 changed-files / changed_files 引数が存在しない
  run bash -c "grep -qE \
    '\-\-changed.files|\-\-pr.files|CHANGED_FILES|changed_files' \
    \"${SCRIPTS_DIR}/specialist-audit.sh\""
  assert_success
}

@test "ac1d: specialist-audit.sh が test-only PR を検出して exit 1 を返す（行動テスト）" {
  # AC: cli/twl/tests/ と plugins/twl/tests/ のみ変更の PR → STATUS=FAIL, exit 1
  # RED: 現在 test-only 検出ロジック未実装のため exit 0 になる

  # フィクスチャ JSONL: test 系ファイルのみ変更
  local issue_dir
  issue_dir="$(mktemp -d)"
  local jsonl_file="${issue_dir}/test.jsonl"
  cat > "${jsonl_file}" <<'JSONL_EOF'
{"step":"merge-gate","issue":9999,"changed_files":["cli/twl/tests/test_foo.py","plugins/twl/tests/bats/test_bar.bats"],"actual_specialists":["worker-red-only-detector"]}
JSONL_EOF

  # specialist-audit.sh を --jsonl 付きで実行（sandbox scripts を使用）
  run bash "${SCRIPTS_DIR}/specialist-audit.sh" \
    --jsonl "${jsonl_file}" \
    --mode merge-gate

  rm -rf "${issue_dir}"

  # RED: 現在 test-only HARD FAIL 未実装のため exit 0（assert_failure が fail する）
  assert_failure
}

# ===========================================================================
# AC2: SUB-5 (#1513) handler 本体補完
#
# twl_list_windows_handler を tools.py に追加し、test_issue_1513 を GREEN 化。
#
# RED: 現在 tools.py に twl_list_windows_handler が存在しない
# GREEN: handler 実装後 PASS
# ===========================================================================

@test "ac2a: tools.py に twl_list_windows_handler 関数定義が存在する" {
  # AC: cli/twl/src/twl/mcp_server/tools.py に twl_list_windows_handler が定義されている
  # RED: 現在 tools.py に関数が存在しないため grep fail
  [ -f "${TOOLS_PY}" ]
  run grep -q "def twl_list_windows_handler" "${TOOLS_PY}"
  assert_success
}

@test "ac2b: tools.py に twl_list_windows MCP tool 関数が存在する（handler 呼び出し wrapper）" {
  # AC: MCP tool として登録される twl_list_windows 関数が存在する
  # RED: 現在未実装のため grep fail
  [ -f "${TOOLS_PY}" ]
  run bash -c "grep -qE 'def twl_list_windows[^_]|twl_list_windows_handler' \"${TOOLS_PY}\""
  assert_success
}

@test "ac2c: tools.py の twl_list_windows_handler が session と format 引数を持つ" {
  # AC: handler シグネチャに session と format が含まれる
  # RED: 現在未実装のため grep fail
  [ -f "${TOOLS_PY}" ]
  run bash -c "grep -A5 'def twl_list_windows_handler' \"${TOOLS_PY}\" | grep -qE 'session|format'"
  assert_success
}

# ===========================================================================
# AC3: worker-issue-pr-alignment specialist の強化
#
# PR の AC 完遂検証で「AC mentioned in body but no impl in diff」を CRITICAL として検出。
# observer 自律 verify SOP に inject。
#
# RED: 現在 worker-issue-pr-alignment.md に "no impl in diff" CRITICAL 検出が存在しない
# GREEN: ロジック追記後 PASS
# ===========================================================================

@test "ac3a: worker-issue-pr-alignment.md に 'no impl in diff' CRITICAL 検出ロジックが記述されている" {
  # AC: 「AC mentioned in body but no impl in diff」を CRITICAL として検出する記述
  # RED: 現在 worker-issue-pr-alignment.md に no-impl-in-diff の明示的 CRITICAL 記述が存在しない
  local agent_file="${AGENTS_DIR}/worker-issue-pr-alignment.md"
  [ -f "${agent_file}" ]
  run bash -c "grep -qiE \
    'no impl.*diff|impl.*not.*diff|AC.*mentioned.*no.*impl|no implementation.*diff|body.*no.*diff' \
    \"${agent_file}\""
  assert_success
}

@test "ac3b: worker-issue-pr-alignment.md に AC 未達成の CRITICAL 判定基準が明示されている" {
  # AC: PR diff に AC の実装が全くない場合の CRITICAL 判定条件が明示されている
  # RED: 現在の記述は「完全未達成（ゼロ言及）」に対する CRITICAL 条件だが、
  #      「AC mentioned in body but no impl in diff」の明示的なフレーズが不足
  local agent_file="${AGENTS_DIR}/worker-issue-pr-alignment.md"
  [ -f "${agent_file}" ]
  run bash -c "grep -cE 'CRITICAL' \"${agent_file}\""
  # CRITICAL が少なくとも 5 箇所存在すること（現在の件数 + AC3 の新規追加分）
  local count
  count="$(grep -cE 'CRITICAL' "${agent_file}" 2>/dev/null || echo 0)"
  [ "${count}" -ge 5 ]
}

@test "ac3c: worker-issue-pr-alignment.md に observer SOP または auto-verify への inject 記述がある" {
  # AC: observer 自律 verify SOP への inject が worker-issue-pr-alignment.md に記述されている
  # RED: 現在 SOP inject に関する記述が存在しない
  local agent_file="${AGENTS_DIR}/worker-issue-pr-alignment.md"
  [ -f "${agent_file}" ]
  run bash -c "grep -qiE \
    'SOP|observer.*verify|auto.verify|verify.*SOP|inject.*observer|observer.*inject' \
    \"${agent_file}\""
  assert_success
}

# ===========================================================================
# AC4: ADR-036 + Invariant N の adherence verify
#
# lesson 構造化チェーンを Worker が自身の PR に適用しているか specialist-audit が check。
#
# RED: 現在 specialist-audit.sh に ADR-036 / Invariant N チェックロジックが存在しない
# GREEN: チェックロジック追加後 PASS
# ===========================================================================

@test "ac4a: specialist-audit.sh に ADR-036 または lesson-structuralization チェックロジックが存在する" {
  # AC: specialist-audit.sh が ADR-036 / Invariant N の adherence を検証するロジックを持つ
  # RED: 現在 specialist-audit.sh に ADR-036 / lesson-structuralization への参照が存在しない
  run bash -c "grep -qiE \
    'ADR-036|lesson.structuralization|Invariant.*N|invariant_n|lesson.*chain.*check' \
    \"${SCRIPTS_DIR}/specialist-audit.sh\""
  assert_success
}

@test "ac4b: specialist-audit.sh が Worker PR の lesson chain 適用状況を検証するパスを持つ" {
  # AC: Worker 自身の PR に lesson 構造化チェーンが適用されているか再帰的に検証
  # RED: 再帰チェックロジック未実装のため grep fail
  run bash -c "grep -qE \
    'lesson.*chain|chain.*lesson|lesson_chain|structuralization.*check|check.*structuralization' \
    \"${SCRIPTS_DIR}/specialist-audit.sh\""
  assert_success
}

@test "ac4c: specialist-audit.sh の ADR-036 チェックが HARD FAIL を返せる" {
  # AC: lesson chain 未適用の PR に対して STATUS=FAIL を返せる
  # RED: ADR-036 HARD FAIL パス未実装のため grep fail
  run bash -c "grep -qE \
    'lesson.*FAIL|FAIL.*lesson|ADR.036.*FAIL|FAIL.*ADR.036|LESSON_CHAIN.*FAIL' \
    \"${SCRIPTS_DIR}/specialist-audit.sh\""
  assert_success
}

# ===========================================================================
# AC5: bats test — specialist-audit.sh の "test scaffold only" + AC unimpl 検出を verify
#
# lesson 19 / 26 の構造化が回帰しないことを保証するテスト。
#
# RED: AC1 / AC4 が未実装のため行動テストが fail する
# GREEN: AC1 + AC4 実装後に PASS
# ===========================================================================

@test "ac5a: specialist-audit.sh が test-only PR を FAIL と判定する（regression guard）" {
  # AC: plugins/twl/tests/ 以下のみ変更 PR → HARD FAIL（lesson 19 regression guard）
  # RED: test-only 検出ロジック未実装のため exit 0（assert_failure が fail する）

  local issue_dir
  issue_dir="$(mktemp -d)"
  local jsonl_file="${issue_dir}/wave-test.jsonl"
  # plugins/twl/tests/ のみ変更、src/ 変更なし
  cat > "${jsonl_file}" <<'JSONL_EOF'
{"step":"merge-gate","issue":8888,"changed_files":["plugins/twl/tests/bats/ac-scaffold-tests-9999.bats","plugins/twl/tests/bats/ac-test-mapping-9999.yaml"],"actual_specialists":["worker-red-only-detector"]}
JSONL_EOF

  run bash "${SCRIPTS_DIR}/specialist-audit.sh" \
    --jsonl "${jsonl_file}" \
    --mode merge-gate

  rm -rf "${issue_dir}"
  # RED: HARD FAIL 未実装のため exit 0 → assert_failure が fail
  assert_failure
}

@test "ac5b: specialist-audit.sh が cli/twl/tests/ のみ変更 PR を FAIL と判定する（regression guard）" {
  # AC: cli/twl/tests/ のみ変更 PR → HARD FAIL（lesson 19 regression guard）
  # RED: test-only 検出ロジック未実装のため exit 0

  local issue_dir
  issue_dir="$(mktemp -d)"
  local jsonl_file="${issue_dir}/cli-test-only.jsonl"
  cat > "${jsonl_file}" <<'JSONL_EOF'
{"step":"merge-gate","issue":7777,"changed_files":["cli/twl/tests/test_foo.py","cli/twl/tests/conftest.py"],"actual_specialists":["worker-red-only-detector"]}
JSONL_EOF

  run bash "${SCRIPTS_DIR}/specialist-audit.sh" \
    --jsonl "${jsonl_file}" \
    --mode merge-gate

  rm -rf "${issue_dir}"
  # RED: HARD FAIL 未実装
  assert_failure
}

@test "ac5c: specialist-audit.sh が src/ を含む正常 PR を PASS と判定する（false positive guard）" {
  # AC: test 系 + src/ 両方変更 PR → PASS（false positive を発生させない）
  # RED: 現在 test-only 検出未実装のため exit 0 だが、このテストは GREEN になるはず
  #      ただし AC1 実装後も false positive が起きないことを保証するためのテスト

  local issue_dir
  issue_dir="$(mktemp -d)"
  local jsonl_file="${issue_dir}/normal-pr.jsonl"
  # src/ への変更あり → test-only FAIL を発動させない
  cat > "${jsonl_file}" <<'JSONL_EOF'
{"step":"merge-gate","issue":6666,"changed_files":["plugins/twl/scripts/specialist-audit.sh","plugins/twl/tests/bats/ac-scaffold-tests-6666.bats"],"actual_specialists":["worker-red-only-detector","worker-security-reviewer"]}
JSONL_EOF

  # このテストは implementation 後に正常 exit 0 になることを確認
  # RED フェーズでは実装がないためこのテスト自体の動作未定義 → 暫定 skip
  # NOTE: AC1 実装後に assert_success として GREEN になること
  run bash "${SCRIPTS_DIR}/specialist-audit.sh" \
    --jsonl "${jsonl_file}" \
    --mode merge-gate
  # 正常 PR は PASS（exit 0）であるべき
  assert_success
}

@test "ac5d: issue-1535 に対応する bats テストファイルが存在する（test scaffold 自身の存在確認）" {
  # AC: ac-scaffold-tests-1535.bats が plugins/twl/tests/bats/ に存在する
  # RED: このファイル自体が存在しない状態（このテストは GREEN になる — 自己参照 bootstrap）
  local test_file="${PLUGIN_ROOT}/tests/bats/ac-scaffold-tests-1535.bats"
  [ -f "${test_file}" ]
}

@test "ac5e: ac-test-mapping-1535.yaml が存在する（AC→test mapping の存在確認）" {
  # AC: ac-test-mapping-1535.yaml が存在し、AC1-AC5 の mapping を含む
  # RED: mapping ファイルが未生成のため fail
  local mapping_file="${PLUGIN_ROOT}/tests/bats/ac-test-mapping-1535.yaml"
  [ -f "${mapping_file}" ]
  run grep -c "ac_index" "${mapping_file}"
  # AC1-AC5 の 5 件以上の mapping が存在すること
  local count
  count="$(grep -c 'ac_index' "${mapping_file}" 2>/dev/null || echo 0)"
  [ "${count}" -ge 5 ]
}
