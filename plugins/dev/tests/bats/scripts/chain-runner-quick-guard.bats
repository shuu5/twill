#!/usr/bin/env bats
# chain-runner-quick-guard.bats - unit tests for chain-runner.sh quick-guard command
#
# Spec: openspec/changes/workflow-test-ready-quick-guard/specs/quick-guard.md
#
# Coverage:
#   1. quick-guard: state に is_quick=true が存在する場合 → exit 1
#   2. quick-guard: state に is_quick=false が存在する場合 → exit 0
#   3. quick-guard: state が未設定で gh API fallback する場合 → exit 1 (quick ラベルあり)
#   4. quick-guard: ブランチから Issue 番号を抽出できない場合 → exit 0（保守的スキップ）
#
# Edge cases:
#   - gh API fallback で quick ラベルなし → exit 0
#   - state-read.sh が空文字を返す + gh API も非 quick → exit 0
#   - 数値以外のブランチ形式でも exit 0 を返す
#   - state-read.sh 失敗時でも exit 0 を返す（フェイルセーフ）

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # デフォルトの git stub: feat/153-quick-guard ブランチを返す（issue_num=153）
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/153-workflow-test-ready-quick-defense" ;;
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

  # デフォルトの gh stub: quick ラベルなし（空出力）
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
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: is_quick フィールドを含む issue-N.json を作成
# ---------------------------------------------------------------------------

_create_issue_with_quick() {
  local issue_num="$1"
  local is_quick="$2"   # "true" or "false" (JSON boolean)

  local file="$SANDBOX/.autopilot/issues/issue-${issue_num}.json"
  mkdir -p "$(dirname "$file")"

  jq -n \
    --argjson issue "$issue_num" \
    --argjson is_quick "$is_quick" \
    '{
      issue: $issue,
      status: "running",
      branch: ("feat/" + ($issue | tostring) + "-test"),
      pr: null,
      window: "",
      started_at: "2026-04-04T00:00:00Z",
      current_step: "ts-preflight",
      retry_count: 0,
      fix_instructions: null,
      merged_at: null,
      files_changed: [],
      failure: null,
      is_quick: $is_quick
    }' > "$file"
}

# ---------------------------------------------------------------------------
# Requirement: chain-runner.sh quick-guard コマンド
# ---------------------------------------------------------------------------

# Scenario: state に is_quick=true が存在する場合
@test "quick-guard: state に is_quick=true が存在する場合は exit 1（quick 判定）" {
  _create_issue_with_quick 153 "true"

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  # exit 1 = quick Issue → ガード発動
  assert_failure
  [ "$status" -eq 1 ]
}

# Scenario: state に is_quick=false が存在する場合
@test "quick-guard: state に is_quick=false が存在する場合は exit 0（非 quick 判定）" {
  _create_issue_with_quick 153 "false"

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  # exit 0 = 非 quick Issue → ガード通過
  assert_success
}

# Scenario: state が未設定で gh API fallback する場合（quick ラベルあり）
@test "quick-guard: state が未設定で gh API fallback → quick ラベルあり → exit 1" {
  # issue-153.json を作成するが is_quick フィールドは含まない（空文字を返す状態）
  local file="$SANDBOX/.autopilot/issues/issue-153.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 153,
    status: "running",
    branch: "feat/153-test",
    pr: null,
    window: "",
    started_at: "2026-04-04T00:00:00Z",
    current_step: "",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$file"

  # gh stub: quick ラベルを返す
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*)
        echo "quick" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  # exit 1 = gh API が quick ラベルを返した
  assert_failure
  [ "$status" -eq 1 ]
}

# Scenario: ブランチから Issue 番号を抽出できない場合
@test "quick-guard: ブランチから Issue 番号を抽出できない場合は exit 0（保守的スキップ）" {
  # git stub: Issue 番号を含まないブランチ名を返す
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/xxx-no-number" ;;
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

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  # exit 0 = Issue 番号なし → 保守的にスキップ
  assert_success
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Edge: state が未設定で gh API fallback → quick ラベルなし → exit 0
@test "quick-guard: state が未設定で gh API fallback → quick ラベルなし → exit 0" {
  # is_quick フィールドなしの JSON
  local file="$SANDBOX/.autopilot/issues/issue-153.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 153,
    status: "running",
    branch: "feat/153-test",
    pr: null,
    window: "",
    started_at: "2026-04-04T00:00:00Z",
    current_step: "",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$file"

  # gh stub: quick ラベルなし（空出力）
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  # exit 0 = gh API も非 quick
  assert_success
}

# Edge: state ファイル自体が存在しない場合は gh API に fallback する
@test "quick-guard: state ファイルが存在しない場合は gh API fallback → quick ラベルあり → exit 1" {
  # issue-153.json を作成しない

  # gh stub: quick ラベルを返す
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*)
        echo "quick" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  assert_failure
  [ "$status" -eq 1 ]
}

# Edge: state ファイルが存在しない + gh API も非 quick → exit 0
@test "quick-guard: state ファイルなし + gh API 非 quick → exit 0" {
  # issue-153.json を作成しない
  # gh stub: quick ラベルなし
  stub_command "gh" 'exit 0'

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  assert_success
}

# Edge: ブランチが main の場合（Issue 番号なし） → exit 0（保守的スキップ）
@test "quick-guard: main ブランチ（Issue 番号なし）の場合は exit 0" {
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "main" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  assert_success
}

# Edge: is_quick フィールドが null の場合は gh API fallback → 非 quick → exit 0
@test "quick-guard: is_quick=null の state は gh API fallback → 非 quick → exit 0" {
  local file="$SANDBOX/.autopilot/issues/issue-153.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 153,
    status: "running",
    branch: "feat/153-test",
    pr: null,
    window: "",
    started_at: "2026-04-04T00:00:00Z",
    current_step: "",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null,
    is_quick: null
  }' > "$file"

  stub_command "gh" 'exit 0'

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  assert_success
}

# Edge: gh api が失敗（ネットワークエラー等）しても exit 0（フェイルセーフ）
@test "quick-guard: gh api 失敗時もフェイルセーフで exit 0" {
  # is_quick フィールドなしの JSON（gh fallback が発火する状態）
  local file="$SANDBOX/.autopilot/issues/issue-153.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 153,
    status: "running",
    branch: "feat/153-test",
    pr: null,
    window: "",
    started_at: "2026-04-04T00:00:00Z",
    current_step: "",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$file"

  # gh stub: exit 1（失敗）
  stub_command "gh" 'exit 1'

  run bash "$SANDBOX/scripts/chain-runner.sh" quick-guard

  # gh 失敗時は非 quick 扱い（保守的）→ exit 0
  assert_success
}
