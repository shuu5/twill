#!/usr/bin/env bats
# ac-scaffold-tests-1540.bats
#
# Issue #1540: meta-bug(autopilot): specialist-audit fix (PR #1537) が chain で active されていない
# Wave 73 で 5 連続 lesson 19 reproduction → auto-merge.sh Layer 5 追加で fix (PR #1541)
#
# AC1: specialist-audit 呼び出し経路の root cause 調査
# AC2: chain workflow で specialist-audit を必ず呼ぶ Hook 追加
# AC3: HARD FAIL 検出が trigger しない場合の log 出力
# AC4: bats test 拡張（chain workflow 経路で specialist-audit が呼ばれる integration test）
# AC5: ADR-036 + Invariant N 真の verify（lesson 19 構造化 fix が main 永続化 + chain active）
#
# RED: AC3（WARN log 未実装）→ GREEN: WARN log 追加後

load 'helpers/common'

SCRIPTS_DIR=""
PLUGIN_ROOT_DIR=""
CHAIN_PY=""
CHAIN_RUNNER=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
  local bats_dir
  bats_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  PLUGIN_ROOT_DIR="$(cd "${tests_dir}/.." && pwd)"
  local repo_git_root
  repo_git_root="$(cd "${PLUGIN_ROOT_DIR}" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  CHAIN_PY="${repo_git_root}/cli/twl/src/twl/autopilot/chain.py"
  CHAIN_RUNNER="${SCRIPTS_DIR}/chain-runner.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: specialist-audit 呼び出し経路の root cause 調査
#
# PR #1537 で specialist-audit.sh に HARD FAIL を追加したが、
# chain workflow で active されていなかった真因を構造的に記録・verify。
# merge-gate-check-spawn.sh が Pilot merge-gate command 経由でしか呼ばれず、
# auto-merge.sh 直接呼び出し経路では bypass されていた。
#
# GREEN: PR #1541 で auto-merge.sh Layer 5 追加済み → これらは GREEN から始まる
# ===========================================================================

@test "ac1a: auto-merge.sh に specialist-audit invoke が Layer 5 として追加されている" {
  # AC: auto-merge.sh の Layer 5 コメントに Issue #1540 が参照されている
  run bash -c "grep -q 'Issue #1540' '${SCRIPTS_DIR}/auto-merge.sh'"
  assert_success
}

@test "ac1b: auto-merge.sh の specialist-audit 呼び出しが merge-gate mode で実行される" {
  # AC: auto-merge.sh が --mode merge-gate で specialist-audit を呼ぶ
  run bash -c "grep -q 'mode merge-gate' '${SCRIPTS_DIR}/auto-merge.sh'"
  assert_success
}

@test "ac1c: merge-gate-check-spawn.sh にも specialist-audit invoke が存在する" {
  # AC: merge-gate-check-spawn.sh が specialist-audit を呼ぶ（既存経路の確認）
  run bash -c "grep -q 'specialist-audit' '${SCRIPTS_DIR}/merge-gate-check-spawn.sh'"
  assert_success
}

@test "ac1d: auto-merge.sh の specialist-audit 呼び出しが Layer 5 として位置づけられている" {
  # AC: auto-merge.sh に "Layer 5" のコメントラベルで specialist-audit が追加されている
  run bash -c "grep -qE 'Layer 5.*specialist-audit|specialist-audit.*Layer 5' \
    '${SCRIPTS_DIR}/auto-merge.sh'"
  assert_success
}

# ===========================================================================
# AC2: chain workflow で specialist-audit を必ず呼ぶ Hook 追加
#
# chain.py CHAIN_STEPS に merge-gate-check を追加し、chain-runner.sh の
# step_merge_gate_check 関数で Worker chain 経由でも specialist-audit を invoke する。
# (Issue #1554 fix: PR #1550 で AC2 未実装のまま merge された真の修正)
#
# GREEN: Issue #1554 実装後
# ===========================================================================

@test "ac2a: chain.py CHAIN_STEPS に merge-gate-check が含まれる（chain SSOT 検証）" {
  # AC: chain.py CHAIN_STEPS に "merge-gate-check" が追加されている (Issue #1554 fix)
  [ -f "${CHAIN_PY}" ]
  run bash -c "grep -qF '\"merge-gate-check\"' '${CHAIN_PY}'"
  assert_success
}

@test "ac2b: chain.py STEP_TO_WORKFLOW で merge-gate-check が pr-merge workflow に紐付けられている" {
  # AC: STEP_TO_WORKFLOW に "merge-gate-check": "pr-merge" エントリが存在する
  [ -f "${CHAIN_PY}" ]
  run bash -c "grep -qE '\"merge-gate-check\".*:.*\"pr-merge\"' '${CHAIN_PY}'"
  assert_success
}

@test "ac2c: chain-runner.sh に step_merge_gate_check 関数が定義されている" {
  # AC: chain-runner.sh に step_merge_gate_check 関数が存在し specialist-audit を invoke する
  [ -f "${CHAIN_RUNNER}" ]
  run bash -c "grep -qE '^step_merge_gate_check\(\)' '${CHAIN_RUNNER}'"
  assert_success
}

@test "ac2d: chain-runner.sh の step_merge_gate_check 関数が specialist-audit を invoke する" {
  # AC: step_merge_gate_check スコープ内に specialist-audit の呼び出しが存在する
  [ -f "${CHAIN_RUNNER}" ]
  run bash -c "awk '/^step_merge_gate_check\(\)/,/^}/' '${CHAIN_RUNNER}' | grep -qF 'specialist-audit'"
  assert_success
}

# ===========================================================================
# AC3: HARD FAIL 検出が trigger しない場合の log 出力
#
# specialist-audit.sh が git diff 取得失敗 / empty 時に明示的な WARN log を出力する。
# 現在は silent skip → debug が困難。
#
# RED: 現在 git diff empty 時の WARN log が未実装 → GREEN: WARN log 追加後
# ===========================================================================

@test "ac3a: specialist-audit.sh が git diff empty 時に WARN log を stderr に出力する" {
  # AC: non-main branch で git diff origin/main..HEAD が空の場合に WARN log を出力する
  # RED: 現在 git diff empty 時に何も出力しないため、WARN が存在しない
  # GREEN: specialist-audit.sh に WARN 追加後に PASS

  # sandbox の git repo を初期化して非 main ブランチを作成（diff なし）
  local test_git_dir
  test_git_dir="$(mktemp -d)"
  # trap でクリーンアップを保証（pushd 失敗時のリーク防止）
  trap "rm -rf '${test_git_dir}'" EXIT

  pushd "$test_git_dir" >/dev/null || { rm -rf "$test_git_dir"; return 1; }

  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  # main commit 作成
  echo "initial" > README.md
  git add README.md
  git commit --quiet -m "initial"
  git branch -M main

  # origin をセルフ参照に設定（git diff origin/main..HEAD が空を返す）
  git remote add origin "$(pwd)"
  git fetch --quiet origin main 2>/dev/null || true

  # feature branch 作成（commits なし = diff empty）
  git checkout --quiet -b feature/test-empty-diff 2>/dev/null
  # feature branch に commit がないため diff は空

  # specialist-audit.sh を sandbox からコピー
  local audit_script="${SANDBOX}/scripts/specialist-audit.sh"
  mkdir -p "${SANDBOX}/scripts"
  cp "${SCRIPTS_DIR}/specialist-audit.sh" "${audit_script}"

  # 実行: git diff が empty な状態で specialist-audit 実行（--jsonl で引数エラー回避）
  local dummy_jsonl="${SANDBOX}/dummy.jsonl"
  echo '{"type":"message","content":"test"}' > "${dummy_jsonl}"
  local stderr_out
  stderr_out="$(bash "${audit_script}" --jsonl "${dummy_jsonl}" --mode merge-gate 2>&1 >/dev/null || true)"

  popd >/dev/null || true

  # WARN: git diff empty の WARN が出力されるべき（日本語「が空」を含む実装に対応）
  echo "$stderr_out" | grep -qiE 'WARN.*git.*diff|WARN.*changed.files|WARN.*diff.*empty|WARN.*が空'
}

@test "ac3b: specialist-audit.sh が main branch 実行時に test-only チェックスキップの WARN を出力する" {
  # AC: main branch で実行した場合、test-only HARD FAIL チェックをスキップする旨を WARN で出力する

  local test_git_dir
  test_git_dir="$(mktemp -d)"
  # trap でクリーンアップを保証
  trap "rm -rf '${test_git_dir}'" EXIT

  pushd "$test_git_dir" >/dev/null || { rm -rf "$test_git_dir"; return 1; }

  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "initial" > README.md
  git add README.md
  git commit --quiet -m "initial"
  git branch -M main

  # main branch のまま実行
  local audit_script="${SANDBOX}/scripts/specialist-audit.sh"
  mkdir -p "${SANDBOX}/scripts"
  cp "${SCRIPTS_DIR}/specialist-audit.sh" "${audit_script}"

  # --jsonl で引数エラー回避
  local dummy_jsonl="${SANDBOX}/dummy.jsonl"
  echo '{"type":"message","content":"test"}' > "${dummy_jsonl}"
  local stderr_out
  stderr_out="$(bash "${audit_script}" --jsonl "${dummy_jsonl}" --mode merge-gate 2>&1 >/dev/null || true)"

  popd >/dev/null || true

  # WARN: main branch では test-only チェックをスキップする旨の WARN が出力されるべき
  echo "$stderr_out" | grep -qiE \
    'WARN.*main.*branch|WARN.*test.only.*skip|WARN.*scaffold.*skip|WARN.*main.*HEAD'
}

@test "ac3c: specialist-audit.sh に git diff empty 時の WARN 出力コードが存在する（静的確認）" {
  # AC: specialist-audit.sh に git diff empty 時の WARN 出力ロジックが存在する
  # RED: 現在 git diff empty 時の WARN が未実装のため grep fail
  run bash -c "grep -qE \
    'WARN.*diff.*empty|WARN.*が空|WARN.*changed.files|WARN.*test.only.*skip|WARN.*main.*branch|WARN.*main.*HEAD' \
    '${SCRIPTS_DIR}/specialist-audit.sh'"
  assert_success
}

# ===========================================================================
# AC4: bats test 拡張（chain workflow 経路 integration test）
#
# auto-merge.sh → specialist-audit の経路が実際に動作することを verify する
# integration test。
#
# GREEN: ac-scaffold-tests-1540.bats 自体の bootstrap + mapping 確認
# ===========================================================================

@test "ac4a: ac-scaffold-tests-1540.bats が存在する（自己参照 bootstrap）" {
  # AC: このファイル自体の存在確認
  local test_file="${PLUGIN_ROOT_DIR}/tests/bats/ac-scaffold-tests-1540.bats"
  [ -f "${test_file}" ]
}

@test "ac4b: ac-test-mapping-1540.yaml が存在し AC1-AC5 の mapping を含む" {
  # AC: ac-test-mapping-1540.yaml が存在し、5 件以上の AC mapping を持つ
  # RED: mapping ファイルが未生成のため fail
  local mapping_file="${PLUGIN_ROOT_DIR}/tests/bats/ac-test-mapping-1540.yaml"
  [ -f "${mapping_file}" ]
  local count
  count="$(grep -c 'ac_index' "${mapping_file}" 2>/dev/null || echo 0)"
  [ "${count}" -ge 5 ]
}

@test "ac4c: chain.py CHAIN_STEPS + chain-runner.sh step_merge_gate_check が整合している（static trace）" {
  # AC: chain.py CHAIN_STEPS に merge-gate-check が含まれ、chain-runner.sh に
  #     step_merge_gate_check 関数が定義されている（Issue #1554 真の修正確認）
  [ -f "${CHAIN_PY}" ]
  [ -f "${CHAIN_RUNNER}" ]

  # chain.py CHAIN_STEPS に merge-gate-check が存在する
  run bash -c "grep -qF '\"merge-gate-check\"' '${CHAIN_PY}'"
  assert_success

  # chain-runner.sh に step_merge_gate_check 関数が定義されている
  run bash -c "grep -qE '^step_merge_gate_check\(\)' '${CHAIN_RUNNER}'"
  assert_success

  # step_merge_gate_check が specialist-audit を invoke する
  run bash -c "awk '/^step_merge_gate_check\(\)/,/^}/' '${CHAIN_RUNNER}' | grep -qF 'specialist-audit'"
  assert_success
}

# ===========================================================================
# AC5: ADR-036 + Invariant N 真の verify
#
# lesson 19 構造化 fix が main 永続化 + chain workflow で active であることの
# end-to-end 確認。commit 存在確認 + 両経路の specialist-audit 呼び出し verify。
#
# GREEN: PR #1541 merge 済み + auto-merge.sh Layer 5 存在 → GREEN から始まる
# ===========================================================================

@test "ac5a: PR #1541 の Layer 5 fix commit が git log に存在する" {
  # AC: fix(auto-merge): specialist-audit invoke を Layer 5 として追加 (PR #1541) が
  #     git log に存在する（revert されていない）
  # commit hash: 947f2c7f
  local repo_root
  repo_root="$(cd "${PLUGIN_ROOT_DIR}/.." && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  [ -n "${repo_root}" ]
  run bash -c "git -C '${repo_root}' log --oneline | grep -q '947f2c7f\|Layer 5.*specialist-audit\|specialist-audit.*Layer 5'"
  assert_success
}

@test "ac5b: auto-merge.sh と merge-gate-check-spawn.sh の両経路で specialist-audit が active" {
  # AC: 両スクリプトに specialist-audit 呼び出しが存在し、lesson 19 bypass が防止されている
  local auto_merge_has_audit
  auto_merge_has_audit=0
  grep -q 'specialist-audit' "${SCRIPTS_DIR}/auto-merge.sh" && auto_merge_has_audit=1

  local spawn_has_audit
  spawn_has_audit=0
  grep -q 'specialist-audit' "${SCRIPTS_DIR}/merge-gate-check-spawn.sh" && spawn_has_audit=1

  [ "${auto_merge_has_audit}" -eq 1 ]
  [ "${spawn_has_audit}" -eq 1 ]
}

@test "ac5c: specialist-audit.sh が test-only PR を HARD FAIL として検出する（regression guard）" {
  # AC: plugins/twl/tests/ のみ変更 PR → HARD FAIL（Wave 73 以降での lesson 19 regression 防止）
  # この test は test-only HARD FAIL logic の回帰ガードとして機能する

  # sandbox git repo で test-only diff を作成
  local test_git_dir
  test_git_dir="$(mktemp -d)"
  # trap でクリーンアップを保証
  trap "rm -rf '${test_git_dir}'" EXIT

  pushd "$test_git_dir" >/dev/null || { rm -rf "$test_git_dir"; return 1; }

  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "initial" > README.md
  git add README.md
  git commit --quiet -m "initial"
  git branch -M main

  # origin を local 参照に設定
  git remote add origin "$(pwd)"
  git fetch --quiet origin main 2>/dev/null || true
  git branch --set-upstream-to=origin/main main 2>/dev/null || true

  # test-only branch 作成
  git checkout --quiet -b fix/test-only-pr

  # test のみのファイルを追加（impl なし）
  mkdir -p "plugins/twl/tests/bats/scripts"
  echo "# test only" > "plugins/twl/tests/bats/scripts/test_ac1540.bats"
  git add .
  git commit --quiet -m "test: add test scaffold only (no impl)"

  # specialist-audit.sh をコピーして実行
  local audit_script="${SANDBOX}/scripts/specialist-audit.sh"
  mkdir -p "${SANDBOX}/scripts"
  cp "${SCRIPTS_DIR}/specialist-audit.sh" "${audit_script}"

  # dummy JSONL で引数エラーを回避し test-only HARD FAIL ロジックに到達させる（ac3a パターン）
  local dummy_jsonl="${SANDBOX}/dummy.jsonl"
  echo '{"type":"message","content":"test"}' > "${dummy_jsonl}"

  local exit_code=0
  bash "${audit_script}" --jsonl "${dummy_jsonl}" --mode merge-gate 2>/dev/null || exit_code=$?

  popd >/dev/null || true

  # HARD FAIL → exit 1 であるべき
  [ "${exit_code}" -ne 0 ]
}

@test "ac5d: lesson 19 resolution が ADR-036 / Invariant N として architecture docs に反映されている" {
  # AC: lesson 19 の構造的解決が architecture docs に記録されている
  local repo_root
  repo_root="$(cd "${PLUGIN_ROOT_DIR}/.." && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  [ -n "${repo_root}" ]

  # ADR-036 または lesson-structuralization に関する記述が architecture/ に存在する
  local has_doc=0
  grep -rlE 'lesson.19|lesson_19|ADR.036|Invariant.*N|invariant_n' \
    "${repo_root}/plugins/twl/architecture/" 2>/dev/null | grep -q . && has_doc=1 || true

  # CLAUDE.md にも lesson 19 の記述がある
  grep -qE 'lesson.19|Invariant.*N' "${repo_root}/plugins/twl/CLAUDE.md" 2>/dev/null && has_doc=1 || true

  [ "${has_doc}" -eq 1 ]
}
