#!/usr/bin/env bats
# chain-runner-next-step.bats - unit tests for next-step command and is_quick persistence
#
# Spec: openspec/changes/chain-runner-next-step-quick/specs/chain-runner-next-step.md
#
# Coverage:
#   1. next-step: 通常 Issue の次ステップ返却 (is_quick=false, current_step=init → board-status-update)
#   2. next-step: quick Issue の QUICK_SKIP_STEPS 除外 (is_quick=true, current_step=board-status-update)
#   3. next-step: 全ステップ完了時 (current_step=最終ステップ → done)
#   4. step_init: quick ラベル付き Issue の is_quick=true 永続化
#   5. step_init: quick ラベルなし Issue の is_quick=false 永続化
#   6. chain-steps.sh: QUICK_SKIP_STEPS 配列のエクスポート確認
#   7. compaction-resume.sh: is_quick=true 時に QUICK_SKIP_STEPS ステップを exit 1 返却
#   8. compaction-resume.sh: is_quick=false 時に通常スキップ判定を実施
#
# Edge cases:
#   - state ファイル不在時の next-step 挙動
#   - is_quick フィールド欠損時のデフォルト false 扱い
#   - CHAIN_STEPS が空でも next-step が done を返す

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # git stub: feat/151 ブランチを返す（issue_num=151 を extract_issue_num で取得させる）
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/151-chain-runnersh-next-step-quick" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  # gh stub: デフォルトは quick ラベルなし (exit 0 + 空出力)
  stub_command "gh" 'exit 0'

  # resolve-project.sh スタブ（chain-runner.sh が source する）
  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "3 PVT_project_id shuu5 loom-plugin-dev shuu5/loom-plugin-dev"
}
RESOLVE_PROJECT
  chmod +x "$SANDBOX/scripts/lib/resolve-project.sh"

  # chain-steps.sh は SANDBOX/scripts/ にコピー済み（common_setup で scripts/*.sh をコピー）
  # state-read.sh / state-write.sh も同様
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: issue-N.json に is_quick フィールドを含めて作成
# ---------------------------------------------------------------------------

_create_issue_with_quick() {
  local issue_num="$1"
  local status="$2"
  local current_step="$3"
  local is_quick="$4"   # "true" or "false" (JSON boolean string)

  local file="$SANDBOX/.autopilot/issues/issue-${issue_num}.json"
  mkdir -p "$(dirname "$file")"

  jq -n \
    --argjson issue "$issue_num" \
    --arg status "$status" \
    --arg current_step "$current_step" \
    --argjson is_quick "$is_quick" \
    '{
      issue: $issue,
      status: $status,
      branch: ("feat/" + ($issue | tostring) + "-test"),
      pr: null,
      window: "",
      started_at: "2026-04-04T00:00:00Z",
      current_step: $current_step,
      retry_count: 0,
      fix_instructions: null,
      merged_at: null,
      files_changed: [],
      failure: null,
      is_quick: $is_quick
    }' > "$file"
}

# ---------------------------------------------------------------------------
# Requirement: next-step コマンドの追加
# ---------------------------------------------------------------------------

# Scenario: 通常 Issue の次ステップ返却
@test "next-step: is_quick=false で current_step=init のとき board-status-update を返す" {
  _create_issue_with_quick 151 "running" "init" "false"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "board-status-update"
}

# Scenario: quick Issue の QUICK_SKIP_STEPS 除外
# board-status-update の次は crg-auto-build → QUICK_SKIP なので skip → ... → change-id-resolve も QUICK_SKIP → ts-preflight
@test "next-step: is_quick=true で current_step=board-status-update のとき QUICK_SKIP_STEPS をスキップして次の非スキップステップを返す" {
  _create_issue_with_quick 151 "running" "board-status-update" "true"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  # QUICK_SKIP_STEPS: crg-auto-build, arch-ref, change-propose, ac-extract, change-id-resolve, test-scaffold, check, change-apply
  # board-status-update の後: crg-auto-build (skip) → arch-ref (skip) → change-propose (skip) → ac-extract (skip)
  # → change-id-resolve (skip) → test-scaffold (skip) → check (skip) → change-apply (skip) → ts-preflight
  assert_output "ts-preflight"
}

# Scenario: 全ステップ完了時
@test "next-step: current_step が最終ステップ (pr-cycle-report) のとき done を返す" {
  _create_issue_with_quick 151 "running" "pr-cycle-report" "false"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "done"
}

# ---------------------------------------------------------------------------
# Edge cases: next-step
# ---------------------------------------------------------------------------

# Edge: state ファイル不在時 → current_step なし → 最初のステップを返す
@test "next-step: state ファイルが存在しない場合は最初のステップ (init) を返す" {
  # issue-151.json を作らない

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "init"
}

# Edge: is_quick フィールドが欠損した state ファイル → デフォルト false 扱い
@test "next-step: is_quick フィールドが欠損している場合は false 扱いで通常順序を返す" {
  # is_quick フィールドを含まない JSON を直接作成
  local file="$SANDBOX/.autopilot/issues/issue-151.json"
  jq -n '{
    issue: 151,
    status: "running",
    branch: "feat/151-test",
    pr: null,
    window: "",
    started_at: "2026-04-04T00:00:00Z",
    current_step: "init",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$file"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "board-status-update"
}

# Edge: quick Issue でも最終ステップ以降なら done を返す
@test "next-step: is_quick=true で current_step が最終ステップのとき done を返す" {
  _create_issue_with_quick 151 "running" "pr-cycle-report" "true"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "done"
}

# Edge: Issue 番号なし (引数なし) → エラー終了
@test "next-step: Issue 番号を省略した場合はエラー終了する" {
  run bash "$SANDBOX/scripts/chain-runner.sh" next-step

  assert_failure
}

# Edge: quick Issue の最初のステップは init (QUICK_SKIP_STEPS 外)
@test "next-step: is_quick=true で current_step 未設定 (初回) のとき init を返す" {
  _create_issue_with_quick 151 "running" "" "true"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "init"
}

# Edge: quick Issue, current_step=init → next は board-status-update (worktree-create は chain から除去済み)
@test "next-step: is_quick=true で current_step=init のとき board-status-update を返す" {
  _create_issue_with_quick 151 "running" "init" "true"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "board-status-update"
}

# ---------------------------------------------------------------------------
# Requirement: is_quick の state 永続化 (step_init)
# ---------------------------------------------------------------------------

# Scenario: quick ラベル付き Issue の永続化
@test "step_init: quick ラベルを検出した場合 is_quick=true が issue-N.json に書き込まれる" {
  # issue-151.json を running 状態で事前作成
  create_issue_json 151 "running"

  # gh stub: quick ラベルを返す
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*)
        echo "quick" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 151

  assert_success

  # is_quick=true が JSON に書き込まれているか確認
  local is_quick
  is_quick=$(jq -r '.is_quick' "$SANDBOX/.autopilot/issues/issue-151.json")
  [ "$is_quick" = "true" ]
}

# Scenario: quick ラベルなし Issue の永続化
@test "step_init: quick ラベルを検出しなかった場合 is_quick=false が issue-N.json に書き込まれる" {
  create_issue_json 151 "running"

  # gh stub: quick ラベルなし (空出力)
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 151

  assert_success

  local is_quick
  is_quick=$(jq -r '.is_quick' "$SANDBOX/.autopilot/issues/issue-151.json")
  [ "$is_quick" = "false" ]
}

# Edge: is_quick 永続化に失敗しても step_init はワークフローを停止しない
@test "step_init: state-write が失敗しても step_init は正常終了する" {
  create_issue_json 151 "running"

  stub_command "gh" 'exit 0'

  # state-write.sh を意図的に失敗させる（is_quick 書き込みのみ失敗）
  cat > "$SANDBOX/scripts/state-write.sh" <<'SWSTUB'
#!/usr/bin/env bash
# --set is_quick= の場合は失敗させる、その他は元の挙動を模倣
if echo "$*" | grep -q "is_quick"; then
  exit 1
fi
exit 0
SWSTUB
  chmod +x "$SANDBOX/scripts/state-write.sh"

  run bash "$SANDBOX/scripts/chain-runner.sh" init 151

  # step_init はエラーを無視して成功終了すること（MUST NOT stop workflow）
  assert_success
}

# Edge: issue 番号なしの init は is_quick 永続化をスキップするが失敗しない
@test "step_init: issue 番号なしで呼んでも異常終了しない" {
  stub_command "gh" 'exit 0'

  run bash "$SANDBOX/scripts/chain-runner.sh" init

  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: QUICK_SKIP_STEPS 配列の追加 (chain-steps.sh)
# ---------------------------------------------------------------------------

# Scenario: QUICK_SKIP_STEPS のエクスポート
@test "chain-steps.sh: source 後に QUICK_SKIP_STEPS 配列が利用可能で必須要素を含む" {
  run bash -c "
    source '$SANDBOX/scripts/chain-steps.sh'

    # 配列が定義されているか
    if [[ \${#QUICK_SKIP_STEPS[@]} -eq 0 ]]; then
      echo 'FAIL: QUICK_SKIP_STEPS is empty or undefined'
      exit 1
    fi

    # 必須要素を確認
    required=(crg-auto-build arch-ref change-propose ac-extract change-id-resolve test-scaffold check change-apply)
    for step in \"\${required[@]}\"; do
      found=false
      for s in \"\${QUICK_SKIP_STEPS[@]}\"; do
        [[ \"\$s\" == \"\$step\" ]] && found=true && break
      done
      if ! \$found; then
        echo \"FAIL: '\$step' not in QUICK_SKIP_STEPS\"
        exit 1
      fi
    done

    echo 'OK'
  "

  assert_success
  assert_output "OK"
}

# Edge: QUICK_SKIP_STEPS に含まれる要素は CHAIN_STEPS にも存在すること（整合性）
@test "chain-steps.sh: QUICK_SKIP_STEPS の全要素は CHAIN_STEPS にも含まれる" {
  run bash -c "
    source '$SANDBOX/scripts/chain-steps.sh'

    for skip_step in \"\${QUICK_SKIP_STEPS[@]}\"; do
      found=false
      for chain_step in \"\${CHAIN_STEPS[@]}\"; do
        [[ \"\$chain_step\" == \"\$skip_step\" ]] && found=true && break
      done
      if ! \$found; then
        echo \"FAIL: QUICK_SKIP_STEPS 要素 '\$skip_step' が CHAIN_STEPS に存在しない\"
        exit 1
      fi
    done

    echo 'OK'
  "

  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# Requirement: compaction-resume.sh の is_quick 対応
# ---------------------------------------------------------------------------

# Scenario: quick Issue での QUICK_SKIP_STEPS スキップ
@test "compaction-resume: is_quick=true の state で change-propose を指定すると exit 1 (スキップ)" {
  # is_quick=true, current_step=change-propose より後のステップを設定
  # compaction-resume は QUICK_SKIP_STEPS ステップを is_quick=true の場合に問答無用でスキップ
  _create_issue_with_quick 151 "running" "ts-preflight" "true"

  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 change-propose

  # exit 1 = スキップ可
  assert_failure
}

# Scenario: 通常 Issue での QUICK_SKIP_STEPS 非スキップ（通常のインデックス比較で判定）
@test "compaction-resume: is_quick=false の state で change-propose は通常のスキップ判定に従う" {
  # is_quick=false, current_step=change-propose より後 → change-propose は完了済みなのでスキップ
  _create_issue_with_quick 151 "running" "ts-preflight" "false"

  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 change-propose

  # change-propose (idx=5) < ts-preflight (idx=11) → スキップ (exit 1)
  assert_failure
}

# Edge: is_quick=false, current_step=change-propose (同じステップ) → 要実行 (exit 0)
@test "compaction-resume: is_quick=false で current_step と同じステップは要実行 (exit 0)" {
  _create_issue_with_quick 151 "running" "change-propose" "false"

  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 change-propose

  # exit 0 = 要実行
  assert_success
}

# Edge: is_quick=true でも QUICK_SKIP_STEPS 外のステップは通常判定に従う
@test "compaction-resume: is_quick=true でも ts-preflight は通常のスキップ判定を行う" {
  # current_step=pr-test (ts-preflight より後) → ts-preflight は完了済みなのでスキップ
  _create_issue_with_quick 151 "running" "pr-test" "true"

  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 ts-preflight

  # ts-preflight は QUICK_SKIP_STEPS 外なので通常判定: ts-preflight < pr-test → スキップ (exit 1)
  assert_failure
}

# Edge: is_quick=true, current_step 未設定 → 要実行 (exit 0)
@test "compaction-resume: is_quick=true で current_step が空なら全ステップ要実行 (exit 0)" {
  _create_issue_with_quick 151 "running" "" "true"

  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 change-propose

  # current_step 未設定 → compaction 未発生 → 要実行
  assert_success
}

# Edge: state ファイル不在時 → 要実行 (exit 0)
@test "compaction-resume: state ファイルが存在しない場合は要実行 (exit 0)" {
  # issue-151.json を作らない

  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 change-propose

  assert_success
}

# Edge: is_quick フィールドが欠損 → デフォルト false として通常判定
@test "compaction-resume: is_quick フィールドが欠損している場合は false 扱い (通常判定)" {
  # is_quick フィールドなしの JSON
  local file="$SANDBOX/.autopilot/issues/issue-151.json"
  jq -n '{
    issue: 151,
    status: "running",
    branch: "feat/151-test",
    pr: null,
    window: "",
    started_at: "2026-04-04T00:00:00Z",
    current_step: "ts-preflight",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$file"

  # change-propose (idx=5) < ts-preflight (idx=11) → スキップ (exit 1)
  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 change-propose

  assert_failure
}

# ---------------------------------------------------------------------------
# Integration: next-step と QUICK_SKIP_STEPS の一貫性
# ---------------------------------------------------------------------------

# quick Issue で next-step が返すステップは QUICK_SKIP_STEPS に含まれない
@test "next-step: quick Issue で返される次ステップは QUICK_SKIP_STEPS に含まれない" {
  _create_issue_with_quick 151 "running" "board-status-update" "true"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  local next_step="$output"

  # next_step が QUICK_SKIP_STEPS に含まれていないことを確認
  run bash -c "
    source '$SANDBOX/scripts/chain-steps.sh'
    next='$next_step'
    for s in \"\${QUICK_SKIP_STEPS[@]}\"; do
      if [[ \"\$s\" == \"\$next\" ]]; then
        echo \"FAIL: '\$next' は QUICK_SKIP_STEPS に含まれている\"
        exit 1
      fi
    done
    echo 'OK'
  "

  assert_success
  assert_output "OK"
}
