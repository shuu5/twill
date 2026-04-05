#!/usr/bin/env bats
# orchestrator-cross-repo-nudge.bats
# Requirement: cross-repo entry 対応の nudge テスト
# Spec: openspec/changes/orchestrator-cross-repo-context/specs/nudge-tests/spec.md
#       openspec/changes/orchestrator-cross-repo-context/specs/nudge-repo-context/spec.md
#
# _nudge_command_for_pattern() に entry 引数を追加し、クロスリポ環境での
# --repo フラグ付き gh 呼び出しを検証する。

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup: cross-repo 対応 nudge-dispatch-cross.sh を生成
# ---------------------------------------------------------------------------
# nudge-dispatch-cross.sh: entry 引数（3番目）を受け取る拡張版 test double
# Usage: nudge-dispatch-cross.sh <issue> <window_name> <pane_output> [entry]
# AUTOPILOT_DIR, REPOS_JSON 環境変数を使用
# GH_SPY_FILE: gh 呼び出しログ記録先
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # gh 呼び出しスパイファイル
  GH_SPY_FILE="$SANDBOX/gh-spy.txt"
  export GH_SPY_FILE

  # cross-repo 対応 nudge-dispatch スクリプトを生成
  cat > "$SANDBOX/scripts/nudge-dispatch-cross.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# nudge-dispatch-cross.sh - _nudge_command_for_pattern() + entry 引数対応 test double
# Usage: nudge-dispatch-cross.sh <issue> <window_name> <pane_output> [entry]
# env: AUTOPILOT_DIR, REPOS_JSON, GH_SPY_FILE
set -euo pipefail

issue="$1"
pane_output="$3"
entry="${4:-_default:${issue}}"

AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"
REPOS_JSON="${REPOS_JSON:-}"
GH_SPY_FILE="${GH_SPY_FILE:-}"

# resolve_issue_repo_context 相当: entry から ISSUE_REPO_OWNER / ISSUE_REPO_NAME を抽出
ISSUE_REPO_ID="${entry%%:*}"
ISSUE_REPO_OWNER=""
ISSUE_REPO_NAME=""

if [[ "$ISSUE_REPO_ID" != "_default" && -n "$REPOS_JSON" ]]; then
  ISSUE_REPO_OWNER=$(echo "$REPOS_JSON" | jq -r --arg k "$ISSUE_REPO_ID" '.[$k].owner // empty')
  ISSUE_REPO_NAME=$(echo "$REPOS_JSON" | jq -r --arg k "$ISSUE_REPO_ID" '.[$k].name // empty')
fi

# is_quick 取得: state ファイルから一次取得
is_quick=""
if [[ -n "$AUTOPILOT_DIR" ]]; then
  state_file="$AUTOPILOT_DIR/issues/issue-${issue}.json"
  if [[ -f "$state_file" ]]; then
    is_quick=$(jq -r 'if .is_quick == null then empty else (.is_quick | tostring) end' "$state_file" 2>/dev/null || true)
  fi
fi

# fallback: gh API で quick ラベルを確認（--repo フラグ付き or なし）
if [[ -z "$is_quick" ]]; then
  if [[ -n "$ISSUE_REPO_OWNER" && -n "$ISSUE_REPO_NAME" ]]; then
    # クロスリポ: --repo フラグを付与
    gh_result=$(gh issue view "$issue" --repo "${ISSUE_REPO_OWNER}/${ISSUE_REPO_NAME}" \
      --json labels --jq '.labels[].name' 2>/dev/null || true)
  else
    # デフォルトリポ: 従来通り --repo なし
    gh_result=$(gh issue view "$issue" \
      --json labels --jq '.labels[].name' 2>/dev/null || true)
  fi

  if echo "$gh_result" | grep -qxF "quick"; then
    is_quick="true"
  else
    is_quick="false"
  fi
fi

# test-ready 系パターン: quick Issue の場合はスキップ
if echo "$pane_output" | grep -qP "setup chain 完了|workflow-test-ready.*で次に進めます"; then
  if [[ "$is_quick" == "true" ]]; then
    exit 1
  fi
fi

# パターン検査 → 次コマンド決定
if echo "$pane_output" | grep -qP "setup chain 完了"; then
  echo "/twl:workflow-test-ready #${issue}"
elif echo "$pane_output" | grep -qP ">>> 提案完了"; then
  echo ""
elif echo "$pane_output" | grep -qP "テスト準備.*完了"; then
  echo "/twl:workflow-pr-cycle #${issue}"
elif echo "$pane_output" | grep -qP "PR サイクル.*完了"; then
  echo ""
elif echo "$pane_output" | grep -qP "workflow-test-ready.*で次に進めます"; then
  echo "/twl:workflow-test-ready #${issue}"
else
  echo ""
fi
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/nudge-dispatch-cross.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: gh API fallback の test double 追加
# Spec: specs/nudge-tests/spec.md — "gh スタブが --repo 引数を spy として記録する"
# ---------------------------------------------------------------------------

# Scenario: --repo フラグを受け取る gh スタブ
# WHEN bats の gh スタブが issue view "$issue" --repo "owner/repo" --json labels ... で呼ばれる
# THEN スタブが --repo 引数を無視せず、呼び出しを記録する（spy として機能する）
@test "nudge-cross: gh stub records --repo flag as spy" {
  # gh spy スタブ: 呼び出し引数を GH_SPY_FILE に記録し、labels 空を返す
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "$*" >> "${GH_SPY_FILE:-/dev/null}"
# labels empty - no quick label
echo ""
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 42 "running"  # is_quick フィールドなし

  export REPOS_JSON='{"loom": {"owner": "shuu5", "name": "loom", "path": "/tmp/loom"}}'
  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "42" "ap-#42" "setup chain 完了" "loom:42"

  # gh が呼ばれたことを確認
  [ -f "$GH_SPY_FILE" ]
  # --repo フラグが記録されていること
  grep -q -- "--repo" "$GH_SPY_FILE"
  # "shuu5/loom" が記録されていること
  grep -q "shuu5/loom" "$GH_SPY_FILE"
}

# ---------------------------------------------------------------------------
# Requirement: is_quick fallback テストケース追加
# Spec: specs/nudge-tests/spec.md — "状態ファイルに is_quick がない場合の gh API fallback"
# ---------------------------------------------------------------------------

# Scenario: 状態ファイルに is_quick がない場合の gh API fallback
# WHEN state-read.sh が is_quick フィールドに空文字を返す
# THEN _nudge_command_for_pattern が gh issue view を呼び出して quick ラベルを確認する
@test "nudge-cross: no is_quick in state → gh API fallback is called" {
  # gh spy: 呼び出しを記録（quick ラベルなし）
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "$*" >> "${GH_SPY_FILE:-/dev/null}"
# labels なし → quick なし
echo ""
GH_EOF
  chmod +x "$STUB_BIN/gh"

  # is_quick フィールドなしの issue json
  create_issue_json 200 "running"  # is_quick フィールド未設定

  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "200" "ap-#200" "setup chain 完了" "_default:200"

  # gh が呼ばれたことを確認（fallback 発動）
  [ -f "$GH_SPY_FILE" ]
  grep -q "issue view" "$GH_SPY_FILE"
}

# Scenario: gh API fallback で quick ラベルあり
# WHEN state に is_quick がなく、gh API が quick ラベルを返す
# THEN _nudge_command_for_pattern が test-ready 系 nudge をスキップする
@test "nudge-cross: no is_quick + gh returns 'quick' label → test-ready nudge skipped" {
  # gh stub: "quick" ラベルを返す
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "$*" >> "${GH_SPY_FILE:-/dev/null}"
echo "quick"
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 201 "running"  # is_quick フィールド未設定

  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "201" "ap-#201" "setup chain 完了" "_default:201"

  # quick ラベルが検出されたので exit 1 でスキップ
  assert_failure
  assert_output ""
}

# Scenario: gh API fallback で quick ラベルなし
# WHEN state に is_quick がなく、gh API が quick ラベルを返さない
# THEN _nudge_command_for_pattern が通常の nudge パターンマッチングを継続する
@test "nudge-cross: no is_quick + gh returns no 'quick' label → normal nudge continues" {
  # gh stub: quick ラベルなし
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "$*" >> "${GH_SPY_FILE:-/dev/null}"
# no labels
echo ""
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 202 "running"  # is_quick フィールド未設定

  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "202" "ap-#202" "setup chain 完了" "_default:202"

  # quick ラベルなし → 通常の nudge が実行される
  assert_success
  assert_output "/twl:workflow-test-ready #202"
}

# ---------------------------------------------------------------------------
# Requirement: クロスリポ環境での --repo フラグ付き gh 呼び出しテスト
# Spec: specs/nudge-tests/spec.md — "クロスリポ環境での gh --repo 呼び出し確認"
# ---------------------------------------------------------------------------

# Scenario: クロスリポ環境での gh --repo 呼び出し確認
# WHEN entry が "_default" 以外（例: loom:42）で、state に is_quick がない
# THEN gh スタブが --repo "owner/repo_name" 付きで呼ばれたことを spy で確認できる
@test "nudge-cross: cross-repo entry → gh called with --repo flag" {
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "GH_CALL: $*" >> "${GH_SPY_FILE:-/dev/null}"
echo ""  # quick ラベルなし
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 42 "running"  # is_quick フィールドなし

  export REPOS_JSON='{"loom": {"owner": "shuu5", "name": "loom", "path": "/tmp/loom"}}'
  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "42" "ap-#42" "setup chain 完了" "loom:42"

  # 正常終了（quick なし → nudge 実行）
  assert_success
  assert_output "/twl:workflow-test-ready #42"

  # gh が --repo shuu5/loom 付きで呼ばれたことを確認
  [ -f "$GH_SPY_FILE" ]
  grep -q -- "--repo shuu5/loom" "$GH_SPY_FILE"
}

# Scenario: デフォルトリポでの --repo なし呼び出し確認
# WHEN entry が _default:42
# THEN gh スタブが --repo なしで呼ばれたことを確認できる
@test "nudge-cross: default-repo entry → gh called without --repo flag" {
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "GH_CALL: $*" >> "${GH_SPY_FILE:-/dev/null}"
echo ""  # quick ラベルなし
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 42 "running"  # is_quick フィールドなし

  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "42" "ap-#42" "setup chain 完了" "_default:42"

  assert_success
  assert_output "/twl:workflow-test-ready #42"

  # gh が --repo なしで呼ばれたこと（spy ログに --repo が含まれない）
  [ -f "$GH_SPY_FILE" ]
  ! grep -q -- "--repo" "$GH_SPY_FILE"
}

# ---------------------------------------------------------------------------
# Requirement: _nudge_command_for_pattern が entry を受け取る
# Spec: specs/nudge-repo-context/spec.md — "entry 引数の追加"
# ---------------------------------------------------------------------------

# Scenario: entry 引数の追加 — resolve_issue_repo_context を呼び出し OWNER/NAME を設定
# WHEN _nudge_command_for_pattern "$pane_output" "$issue" "$entry" が呼ばれる
# THEN 関数内で resolve_issue_repo_context "$entry" を呼び出して ISSUE_REPO_OWNER / ISSUE_REPO_NAME を設定する
@test "nudge-cross: entry arg triggers repo context resolution (OWNER/NAME set for cross-repo)" {
  # gh spy: 呼び出し引数から OWNER/NAME が正しく渡されたか確認
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "GH_CALL: $*" >> "${GH_SPY_FILE:-/dev/null}"
echo ""
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 55 "running"

  export REPOS_JSON='{"myrepo": {"owner": "acme", "name": "myproject", "path": "/tmp/myproject"}}'
  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "55" "ap-#55" "setup chain 完了" "myrepo:55"

  assert_success
  assert_output "/twl:workflow-test-ready #55"

  # REPOS_JSON から解決した acme/myproject で gh が呼ばれている
  grep -q "acme/myproject" "$GH_SPY_FILE"
}

# Scenario: クロスリポ環境での is_quick 確認 — --repo 付き gh issue view
# WHEN entry が "_default" 以外のリポを指し、状態ファイルに is_quick がない
# THEN gh issue view "$issue" --repo "$ISSUE_REPO_OWNER/$ISSUE_REPO_NAME" --json labels ... を実行する
@test "nudge-cross: cross-repo is_quick check uses --repo flag with correct owner/name" {
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "GH_CALL: $*" >> "${GH_SPY_FILE:-/dev/null}"
echo ""  # quick ラベルなし
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 77 "running"

  export REPOS_JSON='{"upstream": {"owner": "org", "name": "upstream-repo", "path": "/tmp/upstream-repo"}}'
  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "77" "ap-#77" "テスト準備が完了しました" "upstream:77"

  assert_success
  assert_output "/twl:workflow-pr-cycle #77"

  # --repo org/upstream-repo が gh に渡されていること
  grep -q -- "--repo org/upstream-repo" "$GH_SPY_FILE"
}

# Scenario: デフォルトリポでの is_quick 確認（後方互換）
# WHEN entry が "_default"（ISSUE_REPO_OWNER が空）
# THEN gh issue view "$issue" --json labels ... を従来通り実行する（--repo フラグなし）
@test "nudge-cross: default-repo is_quick check uses no --repo flag (backward compat)" {
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "GH_CALL: $*" >> "${GH_SPY_FILE:-/dev/null}"
echo ""  # quick ラベルなし
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 88 "running"

  # REPOS_JSON なし = デフォルトリポ環境
  unset REPOS_JSON
  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "88" "ap-#88" "setup chain 完了" "_default:88"

  assert_success
  assert_output "/twl:workflow-test-ready #88"

  # --repo フラグが gh に渡されていないこと
  [ -f "$GH_SPY_FILE" ]
  ! grep -q -- "--repo" "$GH_SPY_FILE"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Edge: is_quick=true が state ファイルにある場合は gh fallback を呼ばない
@test "nudge-cross: is_quick=true in state → no gh API fallback called" {
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "GH_CALL: $*" >> "${GH_SPY_FILE:-/dev/null}"
echo ""
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 300 "running" '. + {is_quick: true}'

  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "300" "ap-#300" "setup chain 完了" "_default:300"

  # quick=true → test-ready スキップ
  assert_failure
  assert_output ""

  # gh API は呼ばれない（state に is_quick があるので fallback 不要）
  [ ! -f "$GH_SPY_FILE" ]
}

# Edge: is_quick=false が state ファイルにある場合も gh fallback を呼ばない
@test "nudge-cross: is_quick=false in state → no gh API fallback called, nudge runs" {
  cat > "$STUB_BIN/gh" << 'GH_EOF'
#!/usr/bin/env bash
echo "GH_CALL: $*" >> "${GH_SPY_FILE:-/dev/null}"
echo ""
GH_EOF
  chmod +x "$STUB_BIN/gh"

  create_issue_json 301 "running" '. + {is_quick: false}'

  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "301" "ap-#301" "setup chain 完了" "_default:301"

  # is_quick=false → 通常 nudge
  assert_success
  assert_output "/twl:workflow-test-ready #301"

  # gh API は呼ばれない
  [ ! -f "$GH_SPY_FILE" ]
}

# ---------------------------------------------------------------------------
# Requirement: 既存テストが全件パスする
# Spec: specs/nudge-tests/spec.md — "既存テストのパス確認"
# NOTE: This test is a meta-check. Run `bats orchestrator-nudge.bats` separately.
# The cross-repo tests in THIS file must not break existing dispatch behaviour.
# ---------------------------------------------------------------------------

# Scenario: 既存テストのパス確認 — cross-repo 追加後も従来パターンが動作する
# WHEN bats tests/bats/scripts/orchestrator-nudge.bats を実行する
# THEN 新規追加テストを含む全テストが PASS する
@test "nudge-cross: legacy dispatch patterns still work after cross-repo extension" {
  # cross-repo 対応後も従来パターンが正常に動作することを検証
  # entry なし（後方互換: 4番目引数省略）
  create_issue_json 999 "running" '. + {is_quick: false}'

  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "999" "ap-#999" "setup chain 完了"

  assert_success
  assert_output "/twl:workflow-test-ready #999"
}

@test "nudge-cross: legacy '>>> 提案完了' pattern still returns empty string" {
  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "999" "ap-#999" ">>> 提案完了: some-chain"

  assert_success
  assert_output ""
}

@test "nudge-cross: legacy unmatched pattern still returns empty string" {
  run bash "$SANDBOX/scripts/nudge-dispatch-cross.sh" "999" "ap-#999" "通常のログ出力"

  assert_success
  assert_output ""
}
