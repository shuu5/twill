#!/usr/bin/env bats
# record-detection-gap.bats
#
# RED-phase tests for Issue #1187:
#   feat(observer): record-detection-gap.sh 新設 — 検知漏れ自動記録 helper
#
# AC coverage:
#   AC4.1 - plugins/twl/skills/su-observer/scripts/record-detection-gap.sh 新規作成
#           (引数: --type, --detail, --related-issue, --severity)
#           (動作1: intervention-log.md 追記, 動作2: doobidoo hint→stderr,
#            動作3: --severity high のみ gh issue create hint→stderr)
#   AC4.2 - bats test (本ファイル) — C1a, C1b, C2, C3
#   AC4.3 - SKILL.md または refs/su-observer-supervise-channels.md に
#            record-detection-gap.sh 呼出 SHOULD 文書化
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir
  bats_dir="$(cd "${this_dir}/.." && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-detection-gap.sh"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  SUPERVISE_CHANNELS="${REPO_ROOT}/skills/su-observer/refs/su-observer-supervise-channels.md"

  export SCRIPT SKILL_MD SUPERVISE_CHANNELS

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
  # SUPERVISOR_DIR は相対パスのみ許可（#1238）。TMPDIR_TEST を CWD にして相対パスで使う
  cd "${TMPDIR_TEST}"
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC4.1: scripts/record-detection-gap.sh 存在・実行可能
# ===========================================================================

@test "ac4.1: record-detection-gap.sh exists at expected path" {
  # AC: plugins/twl/skills/su-observer/scripts/record-detection-gap.sh が新規作成される
  # RED: ファイルが存在しないため fail
  [ -f "${SCRIPT}" ]
}

@test "ac4.1: record-detection-gap.sh is executable" {
  # AC: script が実行可能である
  # RED: ファイルが存在しないため fail
  [ -f "${SCRIPT}" ]
  [ -x "${SCRIPT}" ]
}

@test "ac4.1: record-detection-gap.sh has set -euo pipefail" {
  # AC: set -euo pipefail で安全に実行される（prior art と整合）
  # RED: ファイルが存在しないため fail
  [ -f "${SCRIPT}" ]
  run grep -E 'set -.*e.*u|set -euo' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4.2 C1a: --type test-gap --detail "smoke" --severity medium
#            intervention-log.md 末尾 1 行が ISO 8601 regex にマッチ
# ===========================================================================

@test "ac4.2 C1a: log entry has ISO 8601 timestamp prefix" {
  # AC: log 末尾行が <ISO 8601> [detection-gap] type=test-gap severity=medium: smoke にマッチ
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  local log_file=".supervisor-test/intervention-log.md"
  SUPERVISOR_DIR=".supervisor-test" \
    bash "${SCRIPT}" --type test-gap --detail "smoke" --severity medium
  run tail -1 "${log_file}"
  [[ "${output}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ \[detection-gap\]\ type=test-gap\ severity=medium:\ smoke$ ]]
}

@test "ac4.2 C1a: log entry matches full regex pattern" {
  # AC: 末尾行が \d{4}-...-\d{2}T\d{2}:\d{2}:\d{2}Z \[detection-gap\] type=.* severity=.*: .* にマッチ
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  local log_file=".supervisor-test/intervention-log.md"
  SUPERVISOR_DIR=".supervisor-test" \
    bash "${SCRIPT}" --type test-gap --detail "smoke" --severity medium
  run bash -c "tail -1 '${log_file}' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[detection-gap\] type=[^ ]+ severity=[^:]+: .+\$'"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4.2 C1b: log ファイル不在 → 新規作成 + 1 行 append (mkdir -p で親 dir 作成)
# ===========================================================================

@test "ac4.2 C1b: creates intervention-log.md when file does not exist" {
  # AC: .supervisor/intervention-log.md が存在しない状態で実行 → ファイル新規作成
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  local supervisor_dir=".supervisor-new"
  [ ! -d "${supervisor_dir}" ]
  SUPERVISOR_DIR="${supervisor_dir}" \
    bash "${SCRIPT}" --type missing-monitor --detail "test creation"
  [ -f "${supervisor_dir}/intervention-log.md" ]
}

@test "ac4.2 C1b: creates parent directory with mkdir -p when not exists" {
  # AC: 親ディレクトリが存在しない場合でも mkdir -p で作成される
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  local supervisor_dir="nested/deep/.supervisor"
  [ ! -d "${supervisor_dir}" ]
  SUPERVISOR_DIR="${supervisor_dir}" \
    bash "${SCRIPT}" --type pitfall-miss --detail "deep dir test"
  [ -d "${supervisor_dir}" ]
  [ -f "${supervisor_dir}/intervention-log.md" ]
}

@test "ac4.2 C1b: new file contains exactly one appended line" {
  # AC: 新規作成後のファイルに 1 行（追記分）が存在する
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  local supervisor_dir=".supervisor-c1b"
  SUPERVISOR_DIR="${supervisor_dir}" \
    bash "${SCRIPT}" --type intervention-fail --detail "single line test"
  run wc -l "${supervisor_dir}/intervention-log.md"
  [[ "${output}" =~ ^[[:space:]]*1 ]]
}

# ===========================================================================
# AC4.2 C2: --severity high → stderr に gh issue create を含む hint
#            (hint のみで実起票なし、log 追記は同時に発生)
# ===========================================================================

@test "ac4.2 C2: --severity high outputs gh issue create hint to stderr" {
  # AC: --severity high 実行時に stderr へ gh issue create hint が出力される
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "SUPERVISOR_DIR='.supervisor-test' bash '${SCRIPT}' --type proxy-stuck --detail 'high severity test' --severity high 2>&1 >/dev/null"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "gh issue create" ]]
}

@test "ac4.2 C2: --severity high hint includes required labels" {
  # AC: hint の label に scope/plugins-twl,ctx/supervision,enhancement,P1 が含まれる
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "SUPERVISOR_DIR='.supervisor-test' bash '${SCRIPT}' --type kill-miss --detail 'label check' --severity high 2>&1 >/dev/null"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "scope/plugins-twl" ]]
}

@test "ac4.2 C2: --severity high also appends to intervention-log.md" {
  # AC: --severity high でも動作1（log 追記）が実行される
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  SUPERVISOR_DIR=".supervisor-test" \
    bash "${SCRIPT}" --type kill-miss --detail "high severity log check" --severity high
  [ -f ".supervisor-test/intervention-log.md" ]
  run grep '\[detection-gap\]' ".supervisor-test/intervention-log.md"
  [ "${status}" -eq 0 ]
}

@test "ac4.2 C2: --severity medium does NOT output gh issue create hint" {
  # AC: --severity medium では gh issue create hint は出力されない（high のみ）
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "SUPERVISOR_DIR='.supervisor-test' bash '${SCRIPT}' --type test-gap --detail 'medium check' --severity medium 2>&1 >/dev/null"
  [ "${status}" -eq 0 ]
  [[ ! "${output}" =~ "gh issue create" ]]
}

# ===========================================================================
# AC4.2 C3: 必須引数 (--type または --detail) 欠落時 → exit 1 + stderr に usage
# ===========================================================================

@test "ac4.2 C3: missing --type exits with code 1" {
  # AC: --type が省略されると exit 1 する
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash "${SCRIPT}" --detail "no type provided"
  [ "${status}" -eq 1 ]
}

@test "ac4.2 C3: missing --detail exits with code 1" {
  # AC: --detail が省略されると exit 1 する
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash "${SCRIPT}" --type missing-monitor
  [ "${status}" -eq 1 ]
}

@test "ac4.2 C3: missing --type outputs usage to stderr" {
  # AC: --type 欠落時に stderr へ usage が出力される
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "bash '${SCRIPT}' --detail 'no type' 2>&1 >/dev/null"
  [ "${status}" -eq 1 ]
  [[ "${output}" =~ "--type" ]] || [[ "${output}" =~ "usage" ]] || [[ "${output}" =~ "Usage" ]]
}

@test "ac4.2 C3: missing --detail outputs usage to stderr" {
  # AC: --detail 欠落時に stderr へ usage が出力される
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "bash '${SCRIPT}' --type intervention-fail 2>&1 >/dev/null"
  [ "${status}" -eq 1 ]
  [[ "${output}" =~ "--detail" ]] || [[ "${output}" =~ "usage" ]] || [[ "${output}" =~ "Usage" ]]
}

# ===========================================================================
# AC4.1 動作2: doobidoo memory_store hint が常時 stderr に出力される
# ===========================================================================

@test "ac4.1 action2: doobidoo memory_store hint is output to stderr" {
  # AC: 動作2 — doobidoo memory_store の推奨 content/tags/metadata が stderr に出力される
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "SUPERVISOR_DIR='.supervisor-test' bash '${SCRIPT}' --type test-gap --detail 'hint check' 2>&1 >/dev/null"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "doobidoo" ]] || [[ "${output}" =~ "memory_store" ]] || [[ "${output}" =~ "[hint]" ]]
}

@test "ac4.1 action2: doobidoo hint includes content field" {
  # AC: hint に content フィールドが含まれる
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "SUPERVISOR_DIR='.supervisor-test' bash '${SCRIPT}' --type test-gap --detail 'content check' 2>&1 >/dev/null"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "content" ]] || [[ "${output}" =~ "tags" ]]
}

# ===========================================================================
# AC4.1: --severity default が medium になる
# ===========================================================================

@test "ac4.1: default severity is medium when --severity is not specified" {
  # AC: --severity 未指定時のデフォルトが medium
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  SUPERVISOR_DIR=".supervisor-test" \
    bash "${SCRIPT}" --type test-gap --detail "default severity test"
  run grep 'severity=medium' ".supervisor-test/intervention-log.md"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4.1: --related-issue オプション引数が log に反映される
# ===========================================================================

@test "ac4.1: --related-issue value appears in log or hint output" {
  # AC: --related-issue #N が指定された場合、log または hint に反映される
  # RED: script が存在しないため fail
  [ -f "${SCRIPT}" ]
  run bash -c "SUPERVISOR_DIR='.supervisor-test' bash '${SCRIPT}' --type test-gap --detail 'issue ref test' --related-issue '#1187' 2>&1"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "1187" ]] || grep -q '1187' ".supervisor-test/intervention-log.md" 2>/dev/null
}

# ===========================================================================
# AC4.3: SKILL.md または refs に record-detection-gap.sh 呼出 SHOULD 文書化
# ===========================================================================

@test "ac4.3: SKILL.md or supervise-channels.md documents record-detection-gap.sh call" {
  # AC: SKILL.md または refs/su-observer-supervise-channels.md の Step 1 supervise loop に
  #     「検知漏れ発生時 record-detection-gap.sh 呼出 SHOULD」が明記される
  # RED: 文書化がまだ存在しないため fail
  run bash -c "
    grep -rE 'record-detection-gap' '${SKILL_MD}' '${SUPERVISE_CHANNELS}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac4.3: documentation includes SHOULD keyword for the call" {
  # AC: 文書化に「SHOULD」が含まれる（観察 LLM の判断ポイントとして明記）
  # RED: 文書化がまだ存在しないため fail
  run bash -c "
    grep -A5 -E 'record-detection-gap' '${SKILL_MD}' '${SUPERVISE_CHANNELS}' 2>/dev/null | grep -E 'SHOULD|should'
  "
  [ "${status}" -eq 0 ]
}
