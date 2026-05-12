#!/usr/bin/env bats
# permission-ui-response-safe.bats
#
# Issue #973: tech-debt: observer Auto レイヤーの permission UI menu 自動代理応答対応
#
# AC4 ケース 1: prompt = "Read file foo.md" (safe) → inject "1" 成功 + InterventionRecord 記録
#
# 検証内容:
#   - intervene-auto --pattern permission-ui-response で soft_deny_match を呼ぶ
#   - safe な prompt（Read file foo.md）は no-match → session-comm.sh inject "1" を呼び出す
#   - InterventionRecord が .observation/ に記録される
#
# RED: 全テストは実装前（intervene-auto.md に permission-ui-response パターン未実装）で fail する

load 'helpers/common'

INTERVENE_AUTO_MD=""
SOFT_DENY_MATCH_PY=""
SESSION_COMM_SH=""
FIXTURE_SAFE=""

setup() {
  common_setup

  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  local repo_root
  repo_root="$(cd "${tests_dir}/.." && pwd)"

  INTERVENE_AUTO_MD="${repo_root}/commands/intervene-auto.md"
  SOFT_DENY_MATCH_PY="${repo_root}/../../cli/twl/src/twl/intervention/soft_deny_match.py"
  SESSION_COMM_SH="${repo_root}/../session/scripts/session-comm.sh"
  FIXTURE_SAFE="${this_dir}/fixtures/permission-ui-safe.txt"

  OBSERVATION_DIR="${SANDBOX}/.observation/interventions"
  mkdir -p "${OBSERVATION_DIR}"

  export INTERVENE_AUTO_MD SOFT_DENY_MATCH_PY SESSION_COMM_SH FIXTURE_SAFE OBSERVATION_DIR
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC4 前提: intervene-auto.md に permission-ui-response パターンが存在する
# ===========================================================================

@test "ac4-safe-pre1: intervene-auto.md に --pattern permission-ui-response が定義されている" {
  # AC: intervene-auto.md に新 --pattern permission-ui-response が追加される
  # RED: 未実装のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qF 'permission-ui-response' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac4-safe-pre2: soft_deny_match.py が cli/twl/src/twl/intervention/ に存在する" {
  # AC: cli/twl/intervention/soft_deny_match.py 新設
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]
}

@test "ac4-safe-pre3: intervene-auto.md に soft_deny_match 呼び出しが記述されている" {
  # AC: python3 -m twl.intervention.soft_deny_match 呼び出しが記述される
  # RED: 未実装のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qF 'soft_deny_match' "${INTERVENE_AUTO_MD}"
  assert_success
}

# ===========================================================================
# AC4 ケース 1: safe な prompt → inject "1" + InterventionRecord
# ===========================================================================

@test "ac4-safe-1: permission-ui-safe.txt fixture が存在する" {
  # AC4: fixture: plugins/twl/tests/bats/fixtures/permission-ui-safe.txt
  # このテスト自体は GREEN だが、fixture 依存を明示する
  [ -f "${FIXTURE_SAFE}" ]
}

@test "ac4-safe-2: soft_deny_match は safe fixture に対して no-match を返す" {
  # AC: soft な prompt（Read file）は soft_deny ルールに合致しない → no-match (exit 0)
  # RED: soft_deny_match.py が未実装のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]

  local prompt_context
  prompt_context="$(cat "${FIXTURE_SAFE}")"

  run python3 -m twl.intervention.soft_deny_match \
    --prompt-context "${prompt_context}"
  # no-match は exit 0 かつ stdout に "no-match" を含む
  assert_success
  run grep -qiE 'no.match|PASS|safe|auto-approve' <<< "${output}"
  assert_success
}

@test "ac4-safe-3: intervene-auto.md の no-match 分岐で inject 1 が記述されている" {
  # AC: no-match → session-comm.sh inject $WIN "1" --force で Layer 0 Auto 承認
  # RED: permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'inject.*"1"|inject.*1.*--force|session-comm.*inject.*1' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac4-safe-4: intervene-auto.md の no-match 分岐で BATS_TEST_DIRNAME 経由 fixture 読み込みが記述されている" {
  # AC: fixture を BATS_TEST_DIRNAME 経由で読み込む（実 tmux pane 依存禁止）
  # AC4 の fixture 読み込みパターンが記述されていること
  # RED: permission-ui-response パターンが未実装のため fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  # prompt_context 取得手順が記述されていること
  run grep -qE 'prompt.context|capture.pane.*-S.*-50|capture_pane' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac4-safe-5: intervene-auto.md に InterventionRecord 記録フローが記述されている" {
  # AC: 全分岐で InterventionRecord を .observation/ に記録
  # RED: permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE '\.observation|InterventionRecord|intervention.*record|record.*intervention' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac4-safe-6: intervene-auto --pattern permission-ui-response が safe prompt で Layer 0 Auto 動作をする（統合）" {
  # AC: safe な prompt で inject "1" + InterventionRecord を .observation/ に記録
  # RED: permission-ui-response パターンが未実装のため fail（intervene-auto.md は command spec なのでスクリプト直接実行不可）
  #      静的検証: intervene-auto.md に必要なフロー記述が全て含まれているかを確認する

  [ -f "${INTERVENE_AUTO_MD}" ]

  # permission-ui-response パターン定義
  run grep -qF 'permission-ui-response' "${INTERVENE_AUTO_MD}"
  assert_success

  # soft_deny_match 呼び出し
  run grep -qF 'soft_deny_match' "${INTERVENE_AUTO_MD}"
  assert_success

  # no-match → inject "1" フロー
  run grep -qE 'no.match|no_match' "${INTERVENE_AUTO_MD}"
  assert_success

  # InterventionRecord 記録
  run grep -qE '\.observation|InterventionRecord' "${INTERVENE_AUTO_MD}"
  assert_success
}
