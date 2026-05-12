#!/usr/bin/env bats
# issue-1703-phase-review-cross-pollution.bats
#
# Issue #1703: phase-review.json 共有による cross-pollution で複数 PR が誤 REJECT
#
# AC coverage:
#   AC1: phase-review checkpoint を Worker 単位 isolate
#        merge-gate-check-phase-review.sh が ISSUE_NUMBER env var 経由で
#        per-issue checkpoint (phase-review-{N}.json) を参照すること
#
#   AC2: cross-pollution detection (regression test)
#        並列 Worker 間で review 結果が相互に影響しないこと
#        (Worker A の FAIL が Worker B の merge-gate を REJECT させない)
#
# RED となるテスト (実装前は fail):
#   AC1-a: ISSUE_NUMBER=1692 設定時に phase-review-1692.json を読む → 現状: shared file を読む
#   AC1-b: per-issue PASS + shared FAIL → ISSUE_NUMBER 設定で PASS になる → 現状: REJECT
#   AC2: 5 Worker 並列シミュレーション → 各 Worker が自分の checkpoint を読む → 現状: 全員 shared 読む

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
# Helpers
# ===========================================================================

# checkpoint write helper (uses AUTOPILOT_DIR from common_setup)
_write_checkpoint() {
  local step="$1"
  local ckpt_status="$2"  # renamed from 'status' to avoid conflict with bats $status variable
  local findings="${3:-[]}"
  local issue_number="${4:-}"

  local args=(
    python3 -m twl.autopilot.checkpoint write
    --step "$step"
    --status "$ckpt_status"
    --findings "$findings"
    --autopilot-dir "$AUTOPILOT_DIR"
  )
  if [[ -n "$issue_number" ]]; then
    args+=(--issue-number "$issue_number")
  fi
  run "${args[@]}"
  # $status here is bats run exit code (not ckpt_status)
  [ "$status" -eq 0 ] || return 1
}

# ===========================================================================
# AC1-a: ISSUE_NUMBER env var で per-issue checkpoint ファイルを参照する
# ===========================================================================

@test "ac1-a: ISSUE_NUMBER=1692 設定時に merge-gate-check-phase-review.sh が per-issue checkpoint を読む" {
  local script="${SCRIPTS_DIR}/merge-gate-check-phase-review.sh"
  [ -f "$script" ] || skip "merge-gate-check-phase-review.sh が存在しない"

  # per-issue PASS checkpoint を作成 (Worker B #1692)
  _write_checkpoint "phase-review" "PASS" "[]" "1692"

  # shared FAIL checkpoint を作成 (Worker A の cross-pollution シミュレーション)
  _write_checkpoint "phase-review" "FAIL" \
    '[{"severity":"WARNING","category":"ac_missing","message":"cross-polluted from Worker A"}]' ""

  # ISSUE_NUMBER=1692 で実行 → per-issue PASS を読むので PASS すべき
  # RED: 現状は shared file (FAIL + ac_missing) を読む → REJECT (exit 1)
  ISSUE_NUMBER=1692 run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
  assert_success
}

# ===========================================================================
# AC1-b: per-issue PASS が存在する場合、shared FAIL を無視する
# ===========================================================================

@test "ac1-b: per-issue PASS checkpoint が存在する場合、shared FAIL に影響されない" {
  local script="${SCRIPTS_DIR}/merge-gate-check-phase-review.sh"
  [ -f "$script" ] || skip "merge-gate-check-phase-review.sh が存在しない"

  # Worker A が shared checkpoint を FAIL で書き込み (cross-pollution)
  _write_checkpoint "phase-review" "FAIL" \
    '[{"severity":"WARNING","category":"ac_missing","message":"Worker A: AC1 not found"}]' ""

  # Worker B が per-issue checkpoint を PASS で書き込み
  _write_checkpoint "phase-review" "PASS" "[]" "500"

  # Worker B (ISSUE_NUMBER=500) の merge-gate → per-issue PASS を参照 → exit 0
  # RED: 現状は shared FAIL + ac_missing を読む → REJECT
  ISSUE_NUMBER=500 run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
  assert_success
}

# ===========================================================================
# AC1-c: ISSUE_NUMBER なしの場合は従来動作を維持（shared ファイルを読む）
# ===========================================================================

@test "ac1-c: ISSUE_NUMBER 未設定時は shared checkpoint を読む（後方互換）" {
  local script="${SCRIPTS_DIR}/merge-gate-check-phase-review.sh"
  [ -f "$script" ] || skip "merge-gate-check-phase-review.sh が存在しない"

  # shared PASS checkpoint のみ
  _write_checkpoint "phase-review" "PASS" "[]" ""

  # ISSUE_NUMBER なしで実行 → shared PASS → exit 0
  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
  assert_success
}

@test "ac1-c: ISSUE_NUMBER 未設定かつ shared 不在は REJECT（後方互換）" {
  local script="${SCRIPTS_DIR}/merge-gate-check-phase-review.sh"
  [ -f "$script" ] || skip "merge-gate-check-phase-review.sh が存在しない"

  # shared checkpoint を作成しない → MISSING → REJECT
  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
  assert_failure
  assert_output --partial "REJECT"
}

# ===========================================================================
# AC2: 5 Worker 並列シミュレーション（Wave U.audit-fix-H 事故再現）
# ===========================================================================

@test "ac2: 並列 5 Worker の cross-pollution regression（Wave U.audit-fix-H 再現）" {
  local script="${SCRIPTS_DIR}/merge-gate-check-phase-review.sh"
  [ -f "$script" ] || skip "merge-gate-check-phase-review.sh が存在しない"

  # 5 Worker が全員 per-issue PASS checkpoint を書き込む
  for issue_num in 1691 1692 1693 1694 1699; do
    _write_checkpoint "phase-review" "PASS" "[]" "$issue_num"
  done

  # shared checkpoint に最後の Worker が FAIL + ac_missing を書き込む（cross-pollution シミュレーション）
  printf '%s\n' \
    '{"step":"phase-review","status":"FAIL","findings":[{"severity":"WARNING","category":"ac_missing","message":"shared FAIL: cross-pollution"}],"critical_count":0,"findings_summary":"0 CRITICAL, 1 WARNING","timestamp":"2026-05-12T00:00:00Z"}' \
    > "$AUTOPILOT_DIR/checkpoints/phase-review.json"

  # 各 Worker (ISSUE_NUMBER=N) の merge-gate → per-issue PASS を参照 → 全員 PASS すべき
  # RED: 現状は全員 shared FAIL を読む → 全員 REJECT
  for issue_num in 1691 1692 1693 1694 1699; do
    ISSUE_NUMBER=$issue_num run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
    assert_success  # Worker $issue_num が cross-pollution に影響されず PASS すべき
  done
}

# ===========================================================================
# AC2: merge-gate-checkpoint-merge.sh も per-issue phase-review findings を参照する
# ===========================================================================

@test "ac2: merge-gate-checkpoint-merge.sh が ISSUE_NUMBER で per-issue phase-review findings を参照" {
  local merge_script="${SCRIPTS_DIR}/merge-gate-checkpoint-merge.sh"
  [ -f "$merge_script" ] || skip "merge-gate-checkpoint-merge.sh が存在しない"

  # Worker A の CRITICAL finding を shared phase-review.json に書き込み
  _write_checkpoint "phase-review" "FAIL" \
    '[{"severity":"CRITICAL","confidence":90,"message":"Worker A: critical cross-pollution"}]' ""

  # Worker B の clean per-issue checkpoint
  _write_checkpoint "phase-review" "PASS" "[]" "1692"

  # Worker B の merge-gate-checkpoint-merge: ISSUE_NUMBER=1692 で per-issue を読む
  # → Worker A の CRITICAL finding が含まれないこと
  # RED: 現状は shared を読む → Worker A の CRITICAL が出力に混入
  ISSUE_NUMBER=1692 run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"
  assert_success
  refute_output --partial "Worker A: critical cross-pollution"
}
