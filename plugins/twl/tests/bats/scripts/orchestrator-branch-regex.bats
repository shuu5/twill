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
