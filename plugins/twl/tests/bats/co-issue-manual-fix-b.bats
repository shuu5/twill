#!/usr/bin/env bats
# co-issue-manual-fix-b.bats
#
# RED-phase behavior tests for plugins/twl/scripts/co-issue-manual-fix-b.sh
# Issue #1292: ADR-024 Phase B — co-issue-manual-fix-b.sh から label 付与 step 削除
#
# AC coverage:
#   AC2 - co-issue-manual-fix-b.sh から label 付与 step が消えている (Status=Refined のみ)
#   AC6 - bats test が Status only 期待に書き換えられて全 PASS
#   AC7 - WARN label_add_failed / OK dual_write が消え WARN status_update_failed のみ残る
#   AC8 - 実行時に Status=Refined のみ設定され、refined label が付与されないこと
#
# RED 状態の根拠:
#   現在の co-issue-manual-fix-b.sh は `gh issue edit --add-label refined` を呼ぶため
#   AC2/AC8 の "label 付与なし" アサーションが FAIL する。
#   AC7 static: co-issue-manual-fix-b.sh に dual-write log コードが存在する（削除前）。

load 'helpers/common'

SCRIPT_SRC=""
GH_CALLS_FILE=""
CHAIN_RUNNER_CALLS_FILE=""

setup() {
  common_setup

  # REPO_ROOT = plugins/twl (helpers/common.bash の定義)
  SCRIPT_SRC="${REPO_ROOT}/scripts/co-issue-manual-fix-b.sh"
  GH_CALLS_FILE="${SANDBOX}/gh-calls.log"
  CHAIN_RUNNER_CALLS_FILE="${SANDBOX}/chain-runner-calls.log"

  # gh stub: 全呼び出し引数を記録し常に exit 0 で返す
  cat > "${STUB_BIN}/gh" <<GHEOF
#!/usr/bin/env bash
echo "gh \$*" >> "${GH_CALLS_FILE}"
exit 0
GHEOF
  chmod +x "${STUB_BIN}/gh"

  # chain-runner.sh stub: SCRIPTS_ROOT 配下に配置、呼び出し引数を記録し常に exit 0 で返す
  # common_setup が $REPO_ROOT/scripts/*.sh を $SANDBOX/scripts/ にコピー済みのため上書き
  cat > "${SANDBOX}/scripts/chain-runner.sh" <<CREOF
#!/usr/bin/env bash
echo "chain-runner.sh \$*" >> "${CHAIN_RUNNER_CALLS_FILE}"
exit 0
CREOF
  chmod +x "${SANDBOX}/scripts/chain-runner.sh"
}

teardown() {
  common_teardown
}

# SCRIPTS_ROOT を sandbox に向けてスクリプトを実行するヘルパー
_run_script() {
  local issue_num="${1:-123}"
  local repo="${2:-owner/repo}"
  SCRIPTS_ROOT="${SANDBOX}/scripts" \
    run bash "${SCRIPT_SRC}" "${issue_num}" "${repo}"
}

# ---------------------------------------------------------------------------
# 前提確認
# ---------------------------------------------------------------------------

@test "前提: co-issue-manual-fix-b.sh が存在すること" {
  [ -f "${SCRIPT_SRC}" ]
}

# ---------------------------------------------------------------------------
# AC2: スクリプトから label 付与 step が消えていること（静的内容チェック）
# RED: 現状 L34 に `gh issue edit --add-label refined` が存在するため FAIL
# ---------------------------------------------------------------------------

@test "ac2-static: co-issue-manual-fix-b.sh に --add-label refined が存在しないこと（RED: 現状は存在する）" {
  # AC: Phase B 移行後、label 付与行が削除される
  # RED: 現在 L34 に存在するため fail
  run grep -n '\-\-add-label refined' "${SCRIPT_SRC}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: co-issue-manual-fix-b.sh に --add-label refined が存在する（Phase B では削除必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac2-static: co-issue-manual-fix-b.sh に gh issue edit.*refined が存在しないこと（RED）" {
  # AC: gh issue edit コマンドの refined label 付与が削除される
  # RED: 現在存在するため fail
  run grep -nE 'gh issue edit.*refined' "${SCRIPT_SRC}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: co-issue-manual-fix-b.sh に gh issue edit refined 行が存在する:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac2-static: co-issue-manual-fix-b.sh に board-status-update.*Refined が存在すること（GREEN 保証）" {
  # AC: Status=Refined 設定行は残る（label 付与のみ削除）
  # GREEN: 現在の実装でも存在する → 実装前から PASS
  run grep -c 'board-status-update.*Refined\|Refined.*board-status-update' "${SCRIPT_SRC}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: co-issue-manual-fix-b.sh に board-status-update Refined が存在しない" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC2/AC8: スクリプト実行時に gh issue edit --add-label refined が呼ばれないこと
# RED: 現在の実装は呼ぶため FAIL
# ---------------------------------------------------------------------------

@test "ac2: 実行時に gh issue edit --add-label refined が呼ばれないこと（RED: 現状は呼ばれる）" {
  # AC: Phase B 移行後、label 付与 step が削除される
  # RED: 現在の実装は gh issue edit --add-label refined を呼ぶため fail
  _run_script 123 "owner/repo"

  if grep -qE 'gh issue edit.*--add-label refined|gh issue edit.*refined' "${GH_CALLS_FILE}" 2>/dev/null; then
    echo "FAIL: gh issue edit --add-label refined が呼ばれた（Phase B では禁止）" >&2
    cat "${GH_CALLS_FILE}" >&2
    return 1
  fi
}

@test "ac8: 実行後に refined label が付与されないこと（RED: 現状は付与される）" {
  # AC: 実行後、gh で refined label が付与されない
  # RED: 現在の実装は付与するため fail
  _run_script 456 "test-owner/test-repo"

  local gh_label_calls
  gh_label_calls=$(grep -cE 'gh issue edit.*refined' "${GH_CALLS_FILE}" 2>/dev/null || echo "0")
  gh_label_calls="${gh_label_calls// /}"

  if [ "${gh_label_calls}" -gt 0 ]; then
    echo "FAIL: refined label 付与が ${gh_label_calls} 件検出された（Phase B では 0 件必須）" >&2
    grep -E 'gh issue edit.*refined' "${GH_CALLS_FILE}" >&2 || true
    return 1
  fi
}

@test "ac8: 実行時に gh が 0 回呼ばれること（label 付与なし）（RED: 現状は 1 回以上呼ばれる）" {
  # AC: Phase B では gh issue edit が呼ばれない → 合計 gh 呼び出し = 0
  # RED: 現在の実装は gh issue edit を呼ぶため fail
  _run_script 789 "owner/repo"

  local total_gh_calls
  total_gh_calls=$(wc -l < "${GH_CALLS_FILE}" 2>/dev/null || echo "0")
  total_gh_calls="${total_gh_calls// /}"

  if [ "${total_gh_calls}" -gt 0 ]; then
    echo "FAIL: gh が ${total_gh_calls} 回呼ばれた（Phase B では 0 回必須）" >&2
    cat "${GH_CALLS_FILE}" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC8: Status=Refined が設定されること（GREEN 保証）
# ---------------------------------------------------------------------------

@test "ac8: chain-runner.sh board-status-update Refined が呼ばれること（GREEN 保証）" {
  # AC: Status=Refined は維持される（label 付与のみ削除）
  # GREEN: 現在の実装でも board-status-update は呼ばれる → 実装前から PASS
  _run_script 123 "owner/repo"

  if ! grep -qE 'chain-runner\.sh board-status-update 123 Refined' "${CHAIN_RUNNER_CALLS_FILE}" 2>/dev/null; then
    echo "FAIL: chain-runner.sh board-status-update 123 Refined が呼ばれていない" >&2
    cat "${CHAIN_RUNNER_CALLS_FILE}" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC7: dual-write log コードが削除されること（静的チェック）
# RED: 現在 co-issue-manual-fix-b.sh には dual-write log コードはないが
#      Issue #1292 スコープ内の co-issue-phase4-aggregate.md にはある（AC7 の主対象）
# NOTE: co-issue-manual-fix-b.sh 自体に dual-write log コードがないことを確認
# ---------------------------------------------------------------------------

@test "ac7: co-issue-manual-fix-b.sh に dual-write log コードが存在しないこと（ADR-024 Phase B 整理）" {
  # AC: dual-write log event（WARN label_add_failed / OK dual_write）が削除される
  # NOTE: 現在の co-issue-manual-fix-b.sh は label_add_failed を書いていないが
  #       「Phase B 整理後も残っていないこと」を保証するテスト
  run grep -cE 'label_add_failed|dual_write_log|OK dual_write|refined-dual-write' "${SCRIPT_SRC}"
  local count="${output:-0}"
  count="${count// /}"
  if [ "${count}" -gt 0 ]; then
    echo "FAIL: co-issue-manual-fix-b.sh に dual-write log コードが ${count} 件存在する（Phase B では削除必須）" >&2
    grep -nE 'label_add_failed|dual_write_log|OK dual_write|refined-dual-write' "${SCRIPT_SRC}" >&2 || true
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC6: このファイル自体が Status only 期待のテストとして機能すること（meta test）
# ---------------------------------------------------------------------------

@test "ac6: このテストファイルが Status only 期待のテストであること（meta: テスト名に add-label が存在しないこと）" {
  # AC: co-issue-manual-fix-b.bats が Status only 期待に書き換えられている
  # GREEN: このテスト自体が "label 付与なし" を期待しているため PASS
  # このテストはテストファイルの内容を grep して、label 付与を期待するテスト名が残っていないことを検証
  local self_file="${BATS_TEST_FILENAME}"
  # "add-label refined を期待する（MUST）" といった肯定的な label 付与期待がないことを確認
  run grep -n 'add-label refined.*呼ばれること\|add-label.*MUST\|label 付与.*MUST' "${self_file}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: テストファイルに label 付与を MUST とするテスト名が存在する（Status only 期待に書き換え必要）:" >&2
    echo "${output}" >&2
    return 1
  fi
}
