#!/usr/bin/env bats
# permission-ui-response-deny-escalate.bats
#
# Issue #973: tech-debt: observer Auto レイヤーの permission UI menu 自動代理応答対応
#
# AC4 ケース 3: prompt = "sudo systemctl ..." → STOP + Layer 2 Escalate 昇格
#
# 検証内容:
#   - intervene-auto --pattern permission-ui-response で soft_deny_match を呼ぶ
#   - escalate な prompt（sudo systemctl）は match-escalate → STOP + Layer 2 Escalate 昇格
#   - InterventionRecord が .observation/ に記録される
#   - soft_deny_match.py が privilege-escalation ルール（sudo | chmod +s | setcap）を適用する
#
# RED: 全テストは実装前（soft_deny_match.py 未新設 + intervene-auto.md に未追記）で fail する

load 'helpers/common'

INTERVENE_AUTO_MD=""
SOFT_DENY_MATCH_PY=""
SOFT_DENY_RULES_MD=""
FIXTURE_DENY_ESCALATE=""

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
  SOFT_DENY_RULES_MD="${repo_root}/skills/su-observer/refs/soft-deny-rules.md"
  FIXTURE_DENY_ESCALATE="${this_dir}/fixtures/permission-ui-deny-escalate.txt"

  OBSERVATION_DIR="${SANDBOX}/.observation/interventions"
  mkdir -p "${OBSERVATION_DIR}"

  export INTERVENE_AUTO_MD SOFT_DENY_MATCH_PY SOFT_DENY_RULES_MD FIXTURE_DENY_ESCALATE OBSERVATION_DIR
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC3 前提: soft-deny-rules.md に privilege-escalation ルールが存在する
# ===========================================================================

@test "ac4-escalate-pre1: soft-deny-rules.md に privilege-escalation ルール（layer: escalate）がある" {
  # AC3: privilege-escalation (layer: escalate) — sudo | chmod +s | setcap
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'privilege-escalation' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac4-escalate-pre2: soft-deny-rules.md の privilege-escalation が layer: escalate である" {
  # AC3: privilege-escalation は layer: escalate
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  # privilege-escalation エントリが layer: escalate を持つことを確認
  run grep -qF 'layer: escalate' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac4-escalate-pre3: soft-deny-rules.md の privilege-escalation regex が sudo を含む" {
  # AC3: regex に (sudo |chmod +s|setcap) を含む
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qE 'sudo|chmod.*\+s|setcap' "${SOFT_DENY_RULES_MD}"
  assert_success
}

@test "ac4-escalate-pre4: soft-deny-rules.md の全ルールに必須フィールド（id/regex/layer/rationale）がある" {
  # AC3: 各 rule: id / regex / layer / rationale フィールド必須
  # RED: ファイルが未作成のため fail
  [ -f "${SOFT_DENY_RULES_MD}" ]
  run grep -qF 'id:' "${SOFT_DENY_RULES_MD}"
  assert_success
  run grep -qF 'regex:' "${SOFT_DENY_RULES_MD}"
  assert_success
  run grep -qF 'rationale:' "${SOFT_DENY_RULES_MD}"
  assert_success
}

# ===========================================================================
# AC4 ケース 3: deny-escalate な prompt → match-escalate → STOP + Layer 2 Escalate 昇格
# ===========================================================================

@test "ac4-escalate-1: permission-ui-deny-escalate.txt fixture が存在する" {
  # AC4: fixture: plugins/twl/tests/bats/fixtures/permission-ui-deny-escalate.txt
  [ -f "${FIXTURE_DENY_ESCALATE}" ]
}

@test "ac4-escalate-2: fixture に sudo が含まれている" {
  # fixture の内容確認（BATS_TEST_DIRNAME 経由でアクセス）
  [ -f "${FIXTURE_DENY_ESCALATE}" ]
  run grep -qF 'sudo' "${FIXTURE_DENY_ESCALATE}"
  assert_success
}

@test "ac4-escalate-3: soft_deny_match は deny-escalate fixture に match-escalate を返す" {
  # AC: sudo systemctl は privilege-escalation ルールに一致 → match-escalate (exit 2)
  # RED: soft_deny_match.py が未実装のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]

  local prompt_context
  prompt_context="$(cat "${FIXTURE_DENY_ESCALATE}")"

  run python3 -m twl.intervention.soft_deny_match \
    --prompt-context "${prompt_context}"
  # match-escalate は exit 2（またはそれ以外の非 0）かつ stdout に "match-escalate" を含む
  [ "${status}" -ne 0 ]
  run grep -qiE 'match.escalate|ESCALATE|privilege.escalation' <<< "${output}"
  assert_success
}

@test "ac4-escalate-4: intervene-auto.md に match-escalate → STOP + Layer 2 Escalate 昇格フローが記述されている" {
  # AC: match-escalate → STOP + Layer 2 Escalate 昇格
  # RED: permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'match.escalate|match_escalate|Escalate.*昇格|Layer.*2.*Escalate|escalate.*昇格' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac4-escalate-5: intervene-auto.md に match-escalate 時も InterventionRecord 記録が記述されている" {
  # AC: 全分岐（no-match / match-confirm / match-escalate）で InterventionRecord を .observation/ に記録
  # RED: permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE '\.observation|InterventionRecord' "${INTERVENE_AUTO_MD}"
  assert_success
}

@test "ac4-escalate-6: soft_deny_match.py の exit code が層ごとに異なる（no-match=0, confirm=1, escalate=2）" {
  # AC: soft_deny_match.py の exit code convention を確認
  # RED: soft_deny_match.py が未実装のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]
  # exit code 0=no-match, 1=confirm, 2=escalate の convention がコードに記載されていること
  run grep -qE 'sys\.exit|exit\(0\)|exit\(1\)|exit\(2\)|return.*0|return.*1|return.*2' "${SOFT_DENY_MATCH_PY}"
  assert_success
}

@test "ac4-escalate-7: soft_deny_match.py が escalate 判定時に rule id を stdout に出力する" {
  # AC: soft_deny_match.py は match 時に rule id を出力する（InterventionRecord 記録用）
  # RED: soft_deny_match.py が未実装のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]
  run grep -qE 'rule_id|matched_rule|print.*rule|rule.*print' "${SOFT_DENY_MATCH_PY}"
  assert_success
}

# ===========================================================================
# AC7: ADR-014 3 層プロトコル整合性（soft_deny state tracking）
# ===========================================================================

@test "ac7-escalate-1: soft_deny_match.py が soft-deny-counter.json への記録をサポートする" {
  # AC7: soft_deny state tracking (.observation/<session-id>/soft-deny-counter.json)
  # RED: soft_deny_match.py が未実装のため fail
  [ -f "${SOFT_DENY_MATCH_PY}" ]
  run grep -qE 'soft.deny.counter|counter.*json|deny.*counter' "${SOFT_DENY_MATCH_PY}"
  assert_success
}

@test "ac7-escalate-2: intervene-auto.md に連続 soft_deny 検知時の STOP 動作が記述されている" {
  # AC7: 連続 soft_deny 検知時の STOP 動作
  # RED: permission-ui-response パターンが未記述のため grep fail
  [ -f "${INTERVENE_AUTO_MD}" ]
  run grep -qE 'soft.deny|soft_deny|consecutive.*deny|deny.*count' "${INTERVENE_AUTO_MD}"
  assert_success
}
