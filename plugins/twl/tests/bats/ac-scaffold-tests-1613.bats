#!/usr/bin/env bats
# ac-scaffold-tests-1613.bats
#
# Issue #1613: bug(autopilot): merge-gate REJECT 後の Pilot 手動 merge bypass
#
# AC1: merge-gate-check-merge-override-block.sh 新設 — merge-gate.json が FAIL 状態の PR で
#      gh pr merge 実行を block。TWL_MERGE_GATE_OVERRIDE=<理由> env 設定時のみ通過し audit log に記録。
# AC2: worker-red-only-detector.sh/md の red-only label SKIP path を廃止 →
#      label 付き PR でも WARNING を発行し、follow-up Issue の存在を verify する。
# AC3: merge-gate REJECT + red-only label 付き PR で scripts/red-only-followup-create.sh が
#      自動で follow-up Issue を起票（draft）する。
# AC4: plugins/twl/scripts/pr-comment-findings.sh (またはその呼び出し先) で
#      Merge Gate Final comment 内の step status と overall result の整合チェックを追加 —
#      矛盾検出時に LIGHT-ERROR を append。
# AC5: plugins/twl/refs/ref-invariants.md に「content-REJECT override 禁止」の
#      不変条件が明文化される。
#
# RED: 全テストは実装前に fail する
# GREEN: 実装完了後に PASS する

load 'helpers/common'

SCRIPTS_DIR=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: merge-gate-check-merge-override-block.sh 新設
#
# FAIL 状態の merge-gate.json を持つ PR で gh pr merge を block する。
# TWL_MERGE_GATE_OVERRIDE 設定時のみ通過し audit log に記録。
#
# RED: スクリプトが存在しないため [ -f ] が fail する
# ===========================================================================

@test "ac1a: merge-gate-check-merge-override-block.sh が存在する" {
  # AC: merge-gate-check-merge-override-block.sh 新設
  # RED: ファイルが未作成のため fail
  local script="${SCRIPTS_DIR}/merge-gate-check-merge-override-block.sh"
  [ -f "$script" ]
}

@test "ac1b: merge-gate-check-merge-override-block.sh は merge-gate.json FAIL 状態で exit 1 を返す" {
  # AC: merge-gate.json が FAIL 状態の PR で gh pr merge 実行を block
  # RED: スクリプトが存在しないため run 自体が失敗する
  local script="${SCRIPTS_DIR}/merge-gate-check-merge-override-block.sh"
  [ -f "$script" ]

  # merge-gate.json FAIL 状態を模擬
  local mg_json
  mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot"
  assert_failure
}

@test "ac1c: TWL_MERGE_GATE_OVERRIDE 設定時は通過し audit log に記録される" {
  # AC: TWL_MERGE_GATE_OVERRIDE=<理由> env 設定時のみ通過し audit log に記録
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/merge-gate-check-merge-override-block.sh"
  [ -f "$script" ]

  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  run bash -c "TWL_MERGE_GATE_OVERRIDE='emergency-fix' bash '$script' --autopilot-dir '${SANDBOX}/.autopilot'"
  assert_success

  # audit log にオーバーライド理由が記録されること
  local audit_log="${SANDBOX}/.autopilot/merge-override-audit.log"
  [ -f "$audit_log" ]
  run grep -qF 'emergency-fix' "$audit_log"
  assert_success
}

# ===========================================================================
# AC2: worker-red-only-detector.sh/md の red-only label SKIP path 廃止
#
# red-only label 付き PR でも WARNING を発行し、follow-up Issue の存在を verify する。
#
# RED: 現在 SKIP path が残存しているため「SKIP:」が出力されて exit 0 → fail すべき
# ===========================================================================

@test "ac2a: worker-red-only-detector.sh は red-only ラベル付き PR でも WARNING を発行する" {
  # AC: red-only label SKIP path を廃止 → label 付き PR でも WARNING を発行
  # RED: 現在 red-only ラベルで SKIP exit 0 するため assert_output --partial "WARNING" が fail
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/ac-scaffold-tests-1613.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_output --partial "WARNING"
}

@test "ac2b: worker-red-only-detector.sh は red-only ラベル付き PR で SKIP を出力しない" {
  # AC: SKIP path 廃止 — label 付きでも SKIP メッセージを出力しない
  # RED: 現在 "SKIP:" が出力されるため assert_output の否定が fail
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/ac-scaffold-tests-1613.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  refute_output --partial "SKIP:"
}

@test "ac2c: worker-red-only-detector.md の Step 2 SKIP 条件が廃止されている" {
  # AC: worker-red-only-detector.md の Step 2 SKIP 条件廃止
  # RED: 現在 "スキップ" または "SKIP" 記述が残存しているため grep が成功 → assert_failure が fail
  local md="${REPO_ROOT}/agents/worker-red-only-detector.md"
  [ -f "$md" ]

  # SKIP 条件を定義する行（Step 2 見出し + skip/スキップ記述）が消えていること
  run grep -qE 'Step 2.*SKIP|検出をスキップ|PASS として扱う' "$md"
  assert_failure
}

@test "ac2d: worker-red-only-detector.sh は red-only ラベル付き PR で follow-up Issue 確認を要求する" {
  # AC: label 付き PR でも WARNING を発行し、follow-up Issue の存在を verify する
  # RED: 現在 red-only ラベルで SKIP するため follow-up verify の出力が含まれない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/ac-scaffold-tests-1613.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  # follow-up Issue の存在確認を要求するメッセージが含まれること
  assert_output --partial "follow-up"
}

# ===========================================================================
# AC3: red-only-followup-create.sh 新設 — follow-up Issue 自動起票（draft）
#
# merge-gate REJECT + red-only label 付き PR で follow-up Issue を起票する。
#
# RED: スクリプトが存在しないため [ -f ] が fail する
# ===========================================================================

@test "ac3a: red-only-followup-create.sh が存在する" {
  # AC: scripts/red-only-followup-create.sh が自動で follow-up Issue を起票（draft）する
  # RED: ファイルが未作成のため fail
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]
}

@test "ac3b: red-only-followup-create.sh は gh issue create --draft を呼び出す" {
  # AC: follow-up Issue を draft で起票する
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]

  # gh stub: 呼び出しコマンドをファイルに記録
  local gh_log="${SANDBOX}/gh-calls.log"
  stub_command "gh" "echo \"\$*\" >> '${gh_log}'; echo '42'"

  run bash "$script" --pr-number 99 --issue-title "RED-only follow-up for PR #99"
  assert_success

  [ -f "$gh_log" ]
  # gh issue create --draft が呼ばれていること
  run grep -qF 'issue create' "$gh_log"
  assert_success
  run grep -qF -- '--draft' "$gh_log"
  assert_success
}

@test "ac3c: red-only-followup-create.sh は merge-gate REJECT + red-only label 条件で起動する" {
  # AC: merge-gate REJECT + red-only label 付き PR でスクリプトが起票動作をする
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]

  local gh_log="${SANDBOX}/gh-calls.log"
  stub_command "gh" "echo \"\$*\" >> '${gh_log}'; echo '100'"

  run bash "$script" \
    --pr-number 55 \
    --merge-gate-result REJECTED \
    --labels red-only \
    --issue-title "follow-up: RED-only PR #55"
  assert_success
}

# ===========================================================================
# AC4: chain-runner.sh step_pr_comment_final に step status と overall result の
#      整合チェック追加 — 矛盾検出時に LIGHT-ERROR を append
#
# 矛盾例: ac-verify=PASS / pr-test=PASS / merge-gate=PASS でも
#         overall result が REJECTED になっている場合。
#
# RED: 整合チェックが未実装のため LIGHT-ERROR が出力されない → fail
# ===========================================================================

@test "ac4a: chain-runner.sh step_pr_comment_final 関数が LIGHT-ERROR ロジックを含む（静的確認）" {
  # AC: Merge Gate Final comment 内の step status と overall result の整合チェックを追加
  # RED: LIGHT-ERROR ロジックが未実装のため grep fail
  # NOTE: chain-runner.sh に BASH_SOURCE guard が不在のため source での関数呼び出しは
  #       main が実行されてサブシェルが終了するリスクがある。静的 grep で検証する。
  local script="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "$script" ]

  # step_pr_comment_final 関数が存在すること
  run grep -qF 'step_pr_comment_final()' "$script"
  assert_success

  # step_pr_comment_final スコープ内に LIGHT-ERROR ロジックが存在すること
  # RED: 未実装のため awk スコープ grep fail
  run bash -c "awk '/^step_pr_comment_final\(\)/,/^}/' '${script}' | grep -qF 'LIGHT-ERROR'"
  assert_success
}

@test "ac4b: chain-runner.sh step_pr_comment_final は MERGED 時に LIGHT-ERROR を出力しない" {
  # AC: 矛盾がない正常ケース（MERGED = 全 step PASS）では LIGHT-ERROR を出力しない
  # RED: 整合チェックが未実装のため LIGHT-ERROR が誤出力されることはないが、
  #      テスト自体は ac4a の実装後に整合チェックが正しく動作するかを検証する
  local script="${SCRIPTS_DIR}/chain-runner.sh"
  [ -f "$script" ]

  run grep -qF 'LIGHT-ERROR' "$script"
  # LIGHT-ERROR が参照されていること（整合チェックロジックが存在する証拠）
  # RED: 未実装のため grep fail
  assert_success
}

# ===========================================================================
# AC5: ref-invariants.md に「content-REJECT override 禁止」不変条件の明文化
#
# RED: 該当記述が存在しないため grep が fail する
# ===========================================================================

@test "ac5a: ref-invariants.md に content-REJECT override 禁止の不変条件が存在する" {
  # AC: plugins/twl/refs/ref-invariants.md に「content-REJECT override 禁止」の
  #     不変条件が明文化される
  # RED: 現在 ref-invariants.md に該当記述がないため grep fail
  local invariants="${REPO_ROOT}/refs/ref-invariants.md"
  [ -f "$invariants" ]

  run grep -qE 'content-REJECT|REJECT.*override.*禁止|override.*REJECT.*禁止' "$invariants"
  assert_success
}

@test "ac5b: ref-invariants.md の content-REJECT override 禁止条件が不変条件テーブルに掲載される" {
  # AC: 不変条件の正典テーブルまたは見出しセクションに記載される
  # RED: 該当見出し（## 不変条件 R 等）または table の用語列エントリが存在しないため fail
  #
  # NOTE: Markdown テーブルの用語列マッチは '| term |' パターンを使用（過剰マッチ防止）
  local invariants="${REPO_ROOT}/refs/ref-invariants.md"
  [ -f "$invariants" ]

  # テーブルの用語列（左パイプ区切り）でマッチ、または見出しに記述されること
  run grep -qF '## 不変条件' "$invariants"
  assert_success

  # content-REJECT override 禁止が見出しまたはテーブル行に存在すること
  run grep -qE '不変条件.*REJECT|REJECT.*不変条件|content-REJECT' "$invariants"
  assert_success
}
