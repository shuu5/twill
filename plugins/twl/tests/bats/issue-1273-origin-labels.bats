#!/usr/bin/env bats
# issue-1273-origin-labels.bats
#
# RED-phase tests for Issue #1273:
#   feat(provenance): origin:* label 体系定義 + 既存 Issue 遡及付与 (cross-origin Phase A)
#
# AC coverage:
#   AC1 - origin:host:* / origin:repo:* ラベルが定義済みである（setup-origin-labels.sh が作成コマンドを含む）
#   AC2 - 多段階検索フラグ（--state all --limit 500）が setup-origin-labels.sh に含まれる
#   AC3 - べき等付与（既付与 skip）ロジックが setup-origin-labels.sh に含まれる
#   AC4 - host-aliases.json が ~/.config/twl/ に存在し、3 ホストエントリを含む
#   AC5 - setup-origin-labels.sh が Project Board view filter に関するコメントまたは参照を含む
#   AC6 - setup-origin-labels.sh が plugins/twl/scripts/onboarding/ に存在し、基本要件を満たす
#   AC7 - setup-origin-labels.sh が Issue 件数報告ロジック（3 件超分岐）を含む
#   AC8 - setup-origin-labels.sh が doobidoo memory hash 3c47c84a への言及を含む（INFO）
#
# 全テストは実装前（RED）状態で fail する。
#
# NOTE: setup-origin-labels.sh は source guard
#   ([[ "${BASH_SOURCE[0]}" == "${0}" ]] guard) の存在を確認することを推奨する（baseline-bash.md §10）。
#   本スクリプトは新規作成のため、実装者は guard を追加すること。

load 'helpers/common'

setup() {
  common_setup
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"

  SETUP_SCRIPT="${REPO_ROOT}/scripts/onboarding/setup-origin-labels.sh"
  HOST_ALIASES_JSON="${HOME}/.config/twl/host-aliases.json"
  THIS_BATS="${REPO_ROOT}/tests/bats/issue-1273-origin-labels.bats"

  export REPO_ROOT SETUP_SCRIPT HOST_ALIASES_JSON THIS_BATS
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: origin:host:* / origin:repo:* ラベルが setup-origin-labels.sh に定義されている
# ===========================================================================

@test "ac1: setup-origin-labels.sh exists at expected path" {
  # AC: plugins/twl/scripts/onboarding/setup-origin-labels.sh が存在する
  # RED: ファイルがまだ作成されていないため fail
  [ -f "${SETUP_SCRIPT}" ]
}

@test "ac1: setup-origin-labels.sh contains origin:host:ipatho-1 label" {
  # AC: origin:host:ipatho-1 ラベル作成コマンドが含まれる
  # RED: ファイルが存在しないため fail
  grep -qF 'origin:host:ipatho-1' "${SETUP_SCRIPT}"
}

@test "ac1: setup-origin-labels.sh contains origin:host:ipatho2 label" {
  # AC: origin:host:ipatho2 ラベル作成コマンドが含まれる
  # RED: ファイルが存在しないため fail
  grep -qF 'origin:host:ipatho2' "${SETUP_SCRIPT}"
}

@test "ac1: setup-origin-labels.sh contains origin:host:thinkpad label" {
  # AC: origin:host:thinkpad ラベル作成コマンドが含まれる
  # RED: ファイルが存在しないため fail
  grep -qF 'origin:host:thinkpad' "${SETUP_SCRIPT}"
}

@test "ac1: setup-origin-labels.sh contains origin:repo:soap-copilot-mock label" {
  # AC: origin:repo:soap-copilot-mock ラベル作成コマンドが含まれる
  # RED: ファイルが存在しないため fail
  grep -qF 'origin:repo:soap-copilot-mock' "${SETUP_SCRIPT}"
}

@test "ac1: setup-origin-labels.sh contains origin:repo:twill label" {
  # AC: origin:repo:twill ラベル作成コマンドが含まれる
  # RED: ファイルが存在しないため fail
  grep -qF 'origin:repo:twill' "${SETUP_SCRIPT}"
}

@test "ac1: setup-origin-labels.sh references host label color fef2c0" {
  # AC: origin:host:* ラベルに色 #fef2c0 が指定されている
  # RED: ファイルが存在しないため fail
  grep -qF 'fef2c0' "${SETUP_SCRIPT}"
}

@test "ac1: setup-origin-labels.sh references repo label color bfd4f2" {
  # AC: origin:repo:* ラベルに色 #bfd4f2 が指定されている
  # RED: ファイルが存在しないため fail
  grep -qF 'bfd4f2' "${SETUP_SCRIPT}"
}

@test "ac1: setup-origin-labels.sh uses gh label create or GraphQL mutation" {
  # AC: gh label create コマンドまたは GraphQL mutation でラベルを作成する
  # RED: ファイルが存在しないため fail
  run grep -qE 'gh label create|gh api graphql|api\.github\.com.*labels' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: 多段階検索フラグが setup-origin-labels.sh に含まれる
# ===========================================================================

@test "ac2: setup-origin-labels.sh contains --state all flag" {
  # AC: gh issue list に --state all フラグが含まれる（全数分類のため）
  # RED: ファイルが存在しないため fail
  grep -qF -- '--state all' "${SETUP_SCRIPT}"
}

@test "ac2: setup-origin-labels.sh contains --limit 500 flag" {
  # AC: gh issue list に --limit 500 フラグが含まれる（全数分類のため）
  # RED: ファイルが存在しないため fail
  grep -qF -- '--limit 500' "${SETUP_SCRIPT}"
}

@test "ac2: setup-origin-labels.sh contains cross-repo origin search keywords" {
  # AC: 検索キーワードに soap-copilot / ipatho / thinkpad / observer のいずれかが含まれる
  # RED: ファイルが存在しないため fail
  run grep -qE 'soap-copilot|ipatho|thinkpad|observer|検出元|起源' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: setup-origin-labels.sh contains gh issue view for body retrieval" {
  # AC: 候補 Issue の body を gh issue view --json body で取得するロジックが含まれる（Step 2）
  # RED: ファイルが存在しないため fail
  run grep -qE 'gh issue view.*--json.*body|gh issue view.*body' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: べき等付与ロジックが setup-origin-labels.sh に含まれる
# ===========================================================================

@test "ac3: setup-origin-labels.sh contains idempotency check (skip if already labeled)" {
  # AC: 既付与ラベルを skip するロジックが含まれる（re-run safe）
  # RED: ファイルが存在しないため fail
  run grep -qE 'skip|already|既付与|idempotent|grep.*label|label.*grep' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac3: setup-origin-labels.sh uses gh issue edit with --add-label" {
  # AC: gh issue edit --add-label でラベルを付与する
  # RED: ファイルが存在しないため fail
  run grep -qE 'gh issue edit.*--add-label|--add-label.*origin:' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac3: setup-origin-labels.sh references shuu5/twill repo for label assignment" {
  # AC: --repo shuu5/twill が指定されている
  # RED: ファイルが存在しないため fail
  grep -qF 'shuu5/twill' "${SETUP_SCRIPT}"
}

# ===========================================================================
# AC4: host-aliases.json が ~/.config/twl/ に存在し、3 ホストエントリを含む
# ===========================================================================

@test "ac4: host-aliases.json exists at ~/.config/twl/host-aliases.json" {
  # AC: ~/.config/twl/host-aliases.json が存在する
  # RED: ファイルがまだ作成されていないため fail
  [ -f "${HOST_ALIASES_JSON}" ]
}

@test "ac4: host-aliases.json is valid JSON" {
  # AC: host-aliases.json が有効な JSON である
  # RED: ファイルが存在しないため fail
  run jq '.' "${HOST_ALIASES_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac4: host-aliases.json contains ipatho-server-2 -> ipatho2 mapping" {
  # AC: "ipatho-server-2": "ipatho2" エントリが含まれる
  # RED: ファイルが存在しないため fail
  run jq -e '."ipatho-server-2" == "ipatho2"' "${HOST_ALIASES_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac4: host-aliases.json contains ipatho-server-1 -> ipatho-1 mapping" {
  # AC: "ipatho-server-1": "ipatho-1" エントリが含まれる
  # RED: ファイルが存在しないため fail
  run jq -e '."ipatho-server-1" == "ipatho-1"' "${HOST_ALIASES_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac4: host-aliases.json contains shuu5-thinkpad -> thinkpad mapping" {
  # AC: "shuu5-thinkpad": "thinkpad" エントリが含まれる
  # RED: ファイルが存在しないため fail
  run jq -e '."shuu5-thinkpad" == "thinkpad"' "${HOST_ALIASES_JSON}"
  [ "${status}" -eq 0 ]
}

@test "ac4: host-aliases.json has exactly 3 entries" {
  # AC: エントリが 3 件（ipatho-server-2, ipatho-server-1, shuu5-thinkpad）
  # RED: ファイルが存在しないため fail
  local count
  count="$(jq 'keys | length' "${HOST_ALIASES_JSON}")"
  [ "${count}" -eq 3 ]
}

# ===========================================================================
# AC5: setup-origin-labels.sh が Project Board view filter に関する言及を含む [WARNING]
# ===========================================================================

@test "ac5: setup-origin-labels.sh contains Project Board or project-board reference" {
  # AC: Project Board #6 への言及またはコメントが含まれる（Cross-repo view filter）
  run grep -qiE 'project.?board|project #6|twill-ecosystem|view filter|Cross-repo|ipatho2 host|ipatho-1 host|thinkpad host' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: setup-origin-labels.sh references Cross-repo filter (label:origin:repo:soap-copilot-mock)" {
  # AC5 view filter 個別確認: Cross-repo フィルター
  run grep -qF 'label:origin:repo:soap-copilot-mock' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: setup-origin-labels.sh references ipatho2 host filter (label:origin:host:ipatho2)" {
  # AC5 view filter 個別確認: ipatho2 host 起票フィルター
  run grep -qF 'label:origin:host:ipatho2' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: setup-origin-labels.sh references ipatho-1 host filter (label:origin:host:ipatho-1)" {
  # AC5 view filter 個別確認: ipatho-1 host 起票フィルター
  run grep -qF 'label:origin:host:ipatho-1' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac5: setup-origin-labels.sh references thinkpad host filter (label:origin:host:thinkpad)" {
  # AC5 view filter 個別確認: thinkpad host 起票フィルター
  run grep -qF 'label:origin:host:thinkpad' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: setup-origin-labels.sh が plugins/twl/scripts/onboarding/ に存在し基本要件を満たす [WARNING]
# ===========================================================================

@test "ac6: setup-origin-labels.sh is executable" {
  # AC: setup-origin-labels.sh が実行可能（chmod +x 済み）
  # RED: ファイルが存在しないため fail
  [ -x "${SETUP_SCRIPT}" ]
}

@test "ac6: setup-origin-labels.sh has bash shebang" {
  # AC: #!/usr/bin/env bash または #!/bin/bash shebang が存在する
  # RED: ファイルが存在しないため fail
  run head -1 "${SETUP_SCRIPT}"
  echo "${output}" | grep -qE '^#!/(usr/bin/env bash|bin/bash)'
}

@test "ac6: setup-origin-labels.sh contains --state all --limit 500 as documented in AC6" {
  # AC: AC6 要件として --state all --limit 500 フラグを含むこと
  # RED: ファイルが存在しないため fail
  run grep -qF -- '--state all' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
  run grep -qF -- '--limit 500' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac6: setup-origin-labels.sh is idempotent (no duplicate label assignment on re-run)" {
  # AC: べき等実行可能 - 重複付与ロジックが実装されている
  # RED: ファイルが存在しないため fail
  # 実装者は「既付与 skip」ロジックの存在を確認すること
  run grep -qE 'skip|already.*label|label.*already|existing.*label|label.*exist|gh issue view.*json.*labels' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac6: setup-origin-labels.sh has source guard (BASH_SOURCE check - baseline-bash.md §10)" {
  # AC: source guard [[ "${BASH_SOURCE[0]}" == "${0}" ]] が存在する
  # RED: ファイルが存在しないため fail
  # NOTE: source guard なしで set -euo pipefail 環境で source すると main 到達前に exit する（baseline-bash §10）
  run grep -qE 'BASH_SOURCE\[0\].*==.*\$\{?0\}?|\$\{BASH_SOURCE\[0\]\}.*\$0' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: setup-origin-labels.sh が Issue 件数報告ロジック（3 件超分岐）を含む [INFO]
# ===========================================================================

@test "ac7: setup-origin-labels.sh reports classified issue count" {
  # AC: AC2 で確定した件数をユーザーに報告するロジックが含まれる
  # RED: ファイルが存在しないため fail
  run grep -qE 'echo|printf|report|count|件数|classified|found' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac7: setup-origin-labels.sh has branch for count > 3" {
  # AC: 3 件超の場合に差分を明示する分岐が含まれる
  # RED: ファイルが存在しないため fail
  run grep -qE 'if.*-gt 3|count.*>.*3|\[ .* -gt 3 \]|gt 3' "${SETUP_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8: setup-origin-labels.sh が doobidoo memory hash 3c47c84a への言及を含む [INFO]
# ===========================================================================

@test "ac8: setup-origin-labels.sh mentions doobidoo memory hash 3c47c84a" {
  # AC: doobidoo memory hash 3c47c84a への言及（コメントとして可）が含まれる
  # RED: ファイルが存在しないため fail
  grep -qF '3c47c84a' "${SETUP_SCRIPT}"
}

# ===========================================================================
# self-referential: このテストファイル自体の存在確認
# ===========================================================================

@test "self: this bats test file exists at expected path" {
  # AC: bats ファイルが plugins/twl/tests/bats/issue-1273-origin-labels.bats として存在する
  # GREEN: このファイル自体が存在するため、実行時点では pass する
  [ -f "${THIS_BATS}" ]
}

@test "self: this bats test file contains at least 10 test blocks" {
  # AC: 本ファイルに 10 件以上の @test ブロックが含まれる
  # GREEN: このファイルが書き出された時点で pass する
  local count
  count="$(grep -c '^@test ' "${THIS_BATS}")"
  [ "${count}" -ge 10 ]
}
