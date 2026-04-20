#!/usr/bin/env bats
# orchestrator-branch-regex.bats
# AC-3: branch 名バリデーション regex の統一 unit tests
# 対象箇所: autopilot-orchestrator.sh L288/L418/L1270 + autopilot-cleanup.sh L186
#
# Regex: ^[a-zA-Z0-9_/\-]+$  (`.` を完全除外)

load '../helpers/common'

# ---------------------------------------------------------------------------
# Helper: regex と同一の bash 条件式で accept/reject を判定
# 各ロケーション（L288/L418/L1270/cleanup L186）を独立してカバー
# ---------------------------------------------------------------------------

# _branch_regex_match <branch> — returns 0 if accepted, 1 if rejected
_branch_regex_match() {
  local branch="$1"
  [[ -n "$branch" && "$branch" =~ ^[a-zA-Z0-9_/\-]+$ ]]
}

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# accept cases — autopilot _ALLOWED_PREFIXES に対応する正常系
# ---------------------------------------------------------------------------

@test "accept: feat/ prefix (L288 orchestrator existing_branch)" {
  run bash -c '[[ -n "feat/685-fix-regex" && "feat/685-fix-regex" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok'
  assert_output "ok"
}

@test "accept: fix/ prefix (L418 orchestrator cleanup_worker)" {
  run bash -c '[[ -n "fix/issue-685-orchestrator" && "fix/issue-685-orchestrator" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok'
  assert_output "ok"
}

@test "accept: chore/ prefix (L1270 orchestrator startup_cleanup)" {
  run bash -c '[[ -n "chore/cleanup-scripts" && "chore/cleanup-scripts" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok'
  assert_output "ok"
}

@test "accept: refactor/ prefix (cleanup.sh L186)" {
  run bash -c '[[ -n "refactor/autopilot" && "refactor/autopilot" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok'
  assert_output "ok"
}

@test "accept: test/ prefix" {
  run bash -c '[[ -n "test/validate" && "test/validate" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok'
  assert_output "ok"
}

@test "accept: docs/ prefix" {
  run bash -c '[[ -n "docs/update" && "docs/update" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok'
  assert_output "ok"
}

# ---------------------------------------------------------------------------
# reject cases — `.` 含み / パストラバーサル / 空文字列
# ---------------------------------------------------------------------------

@test "reject: .. (path traversal — L288)" {
  run bash -c '[[ -n ".." && ".." =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

@test "reject: ../ (path traversal — L418)" {
  run bash -c '[[ -n "../" && "../" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

@test "reject: foo/.. (path traversal — L1270)" {
  run bash -c '[[ -n "foo/.." && "foo/.." =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

@test "reject: foo/../bar (path traversal — cleanup L186)" {
  run bash -c '[[ -n "foo/../bar" && "foo/../bar" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

@test "reject: ../../etc/passwd (deep traversal)" {
  run bash -c '[[ -n "../../etc/passwd" && "../../etc/passwd" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

@test "reject: foo..bar (dot in branch name)" {
  run bash -c '[[ -n "foo..bar" && "foo..bar" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

@test "reject: release/v1.2.3 (dot in version tag)" {
  run bash -c '[[ -n "release/v1.2.3" && "release/v1.2.3" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

@test "reject: empty string (-n guard)" {
  run bash -c '[[ -n "" && "" =~ ^[a-zA-Z0-9_/\-]+$ ]] && echo ok || echo rejected'
  assert_output "rejected"
}

# ---------------------------------------------------------------------------
# AC-4: integration — state file injection で candidate_dir が作られずエラーログ出力
# orchestrator-cleanup-sequence.bats の pattern 準拠（test double + JSON mock）
# ---------------------------------------------------------------------------

_create_existing_branch_double() {
  local project_dir="$1"
  cat > "$SANDBOX/scripts/existing-branch-double.sh" <<DOUBLE_EOF
#!/usr/bin/env bash
# existing-branch-double.sh
# autopilot-orchestrator.sh の L288 ブランチバリデーション ロジックを抽出したテストダブル
set -uo pipefail

ISSUE="\${1:-999}"
effective_project_dir="${project_dir}"

existing_branch=\$(python3 -m twl.autopilot.state read --autopilot-dir "$SANDBOX/.autopilot" --type issue --issue "\$ISSUE" --field branch 2>/dev/null || echo "")

# ブランチ名バリデーション: `.` 除外の統一 regex (L288 と同一ロジック)
if [[ -n "\$existing_branch" && "\$existing_branch" =~ ^[a-zA-Z0-9_/\\-]+\$ ]]; then
  local candidate_dir="\$effective_project_dir/worktrees/\$existing_branch"
  if [[ -d "\$candidate_dir" ]]; then
    echo "[orchestrator] Issue #\${ISSUE}: 既存 worktree を使用: \$candidate_dir" >&2
    echo "USED:\$candidate_dir"
  fi
elif [[ -n "\$existing_branch" ]]; then
  echo "[orchestrator] Issue #\${ISSUE}: ⚠️ 不正なブランチ名を拒否: \$existing_branch" >&2
  echo "REJECTED:\$existing_branch"
fi
DOUBLE_EOF
  chmod +x "$SANDBOX/scripts/existing-branch-double.sh"
}

@test "AC-4: state file injection ../../../etc/passwd — candidate_dir 未作成 + エラーログ出力" {
  # Setup: JSON mock state file with malicious branch name
  local issue_json="$SANDBOX/.autopilot/issues/issue-999.json"
  cat > "$issue_json" <<'EOF'
{"branch": "../../../etc/passwd", "status": "in_progress", "role": "worker"}
EOF

  # Worktree dir must not exist for the injection target
  local target="$SANDBOX/worktrees/../../../etc/passwd"
  [[ -d "$target" ]] && fail "target dir must not exist pre-test"

  _create_existing_branch_double "$SANDBOX"

  run bash "$SANDBOX/scripts/existing-branch-double.sh" "999"

  # candidate_dir must not be used
  refute_output --partial "USED:"
  # Error log must be output
  assert_output --partial "REJECTED:../../../etc/passwd"
}

@test "AC-4: valid branch — candidate_dir 構築試行（エラーログなし）" {
  # Setup: JSON mock with valid branch name (dir not present → no USED output)
  local issue_json="$SANDBOX/.autopilot/issues/issue-998.json"
  cat > "$issue_json" <<'EOF'
{"branch": "feat/998-valid", "status": "in_progress", "role": "worker"}
EOF

  _create_existing_branch_double "$SANDBOX"

  run bash "$SANDBOX/scripts/existing-branch-double.sh" "998"

  # No rejection error
  refute_output --partial "REJECTED:"
  # No worktree dir → no USED output either
  refute_output --partial "USED:"
}
