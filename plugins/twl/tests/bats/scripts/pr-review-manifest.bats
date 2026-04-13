#!/usr/bin/env bats
# pr-review-manifest.bats - unit tests for scripts/pr-review-manifest.sh

load '../helpers/common'

setup() {
  common_setup

  # Create a git repo in sandbox (for PROJECT_ROOT resolution)
  git init "$SANDBOX" 2>/dev/null
  (cd "$SANDBOX" && git commit --allow-empty -m "initial" 2>/dev/null) || true
  export PROJECT_ROOT="$SANDBOX"

  # Default codex stub: "Not logged in" (tests that need logged-in state override this)
  cat > "$STUB_BIN/codex" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "login" && "$2" == "status" ]]; then
  echo "Not logged in"
  exit 1
fi
exit 0
STUB
  chmod +x "$STUB_BIN/codex"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: --mode が必須
# ===========================================================================

@test "pr-review-manifest requires --mode" {
  run bash "$SANDBOX/scripts/pr-review-manifest.sh"
  assert_failure
}

@test "pr-review-manifest rejects invalid mode" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode invalid"
  assert_failure
}

# ===========================================================================
# Requirement: post-fix-verify モード
# ===========================================================================

@test "post-fix-verify includes code-reviewer and security-reviewer" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
  assert_success
  assert_output --partial "worker-code-reviewer"
  assert_output --partial "worker-security-reviewer"
}

@test "post-fix-verify does not include worker-structure" {
  run bash -c "echo 'deps.yaml' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
  assert_success
  refute_output --partial "worker-structure"
}

@test "post-fix-verify excludes codex when codex login status reports not logged in" {
  # codex stub: login status → "Not logged in"
  cat > "$STUB_BIN/codex" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "login" && "$2" == "status" ]]; then
  echo "Not logged in"
  exit 1
fi
exit 0
STUB
  chmod +x "$STUB_BIN/codex"

  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
  assert_success
  refute_output --partial "worker-codex-reviewer"
}

@test "post-fix-verify includes codex when codex login status reports logged in" {
  # codex stub: login status → "Logged in"
  cat > "$STUB_BIN/codex" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "login" && "$2" == "status" ]]; then
  echo "Logged in as user"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/codex"

  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
  assert_success
  assert_output --partial "worker-codex-reviewer"
}

# ===========================================================================
# Requirement: phase-review モード - 基本ルール
# ===========================================================================

@test "phase-review: deps.yaml change adds worker-structure and worker-principles" {
  run bash -c "echo 'plugins/twl/deps.yaml' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-structure"
  assert_output --partial "worker-principles"
}

@test "phase-review: code change adds worker-code-reviewer and worker-security-reviewer" {
  run bash -c "echo 'src/index.ts' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-code-reviewer"
  assert_output --partial "worker-security-reviewer"
}

@test "phase-review: no code change returns no specialist on stdout" {
  run bash -c "echo 'README.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review 2>/dev/null"
  assert_success
  assert_output ""
}

@test "phase-review: empty input returns no specialist on stdout" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review 2>/dev/null"
  assert_success
  assert_output ""
}

# ===========================================================================
# Requirement: merge-gate モード - architecture/ チェック
# ===========================================================================

@test "merge-gate: architecture/ exists adds worker-architecture" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-architecture"
}

@test "merge-gate: no architecture/ does not add worker-architecture" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  refute_output --partial "worker-architecture"
}

@test "phase-review: architecture/ does not affect phase-review" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  refute_output --partial "worker-architecture"
}

# ===========================================================================
# Requirement: 出力は重複なし
# ===========================================================================

@test "phase-review: output has no duplicates" {
  run bash -c "printf 'deps.yaml\nlib/deps.yaml\n' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success

  # Count occurrences of worker-structure
  local count
  count=$(echo "$output" | grep -c "worker-structure" || true)
  [ "$count" -eq 1 ]
}

@test "post-fix-verify: output has no duplicates" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
  assert_success

  local count
  count=$(echo "$output" | grep -c "worker-code-reviewer" || true)
  [ "$count" -eq 1 ]
}

# ===========================================================================
# Requirement: tech-stack-detect.sh の内部呼び出し（R ファイル）
# ===========================================================================

@test "phase-review: R file detected via tech-stack-detect" {
  # Ensure tech-stack-detect.sh works within the sandbox git project
  # Create a mini git repo in sandbox
  (cd "$SANDBOX" && git init . 2>/dev/null || true)

  run bash -c "cd '$SANDBOX' && printf 'analysis.R\n' | bash scripts/pr-review-manifest.sh --mode phase-review"
  assert_success
  assert_output --partial "worker-r-reviewer"
}

@test "phase-review: supabase migration detected via tech-stack-detect" {
  (cd "$SANDBOX" && git init . 2>/dev/null || true)

  run bash -c "cd '$SANDBOX' && printf 'supabase/migrations/001.sql\n' | bash scripts/pr-review-manifest.sh --mode phase-review"
  assert_success
  assert_output --partial "worker-supabase-migration-checker"
}

# ===========================================================================
# Requirement: worker-issue-pr-alignment 常時必須（Issue 番号が解決可能なとき）
# ===========================================================================

@test "merge-gate: includes worker-issue-pr-alignment when WORKER_ISSUE_NUM set" {
  run bash -c "export WORKER_ISSUE_NUM=135; echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-issue-pr-alignment"
}

@test "phase-review: includes worker-issue-pr-alignment when WORKER_ISSUE_NUM set" {
  run bash -c "export WORKER_ISSUE_NUM=135; echo 'src/index.ts' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-issue-pr-alignment"
}

@test "merge-gate: skips worker-issue-pr-alignment when issue number unresolvable" {
  # Empty AUTOPILOT_DIR + non-issue branch + no WORKER_ISSUE_NUM
  run bash -c "unset WORKER_ISSUE_NUM AUTOPILOT_DIR; cd '$SANDBOX' && (git checkout -b plain-branch 2>/dev/null || true); echo '' | bash scripts/pr-review-manifest.sh --mode merge-gate 2>/dev/null"
  assert_success
  refute_output --partial "worker-issue-pr-alignment"
}

@test "post-fix-verify: does not include worker-issue-pr-alignment" {
  run bash -c "export WORKER_ISSUE_NUM=135; echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
  assert_success
  refute_output --partial "worker-issue-pr-alignment"
}

@test "merge-gate: skip warning logged to stderr when issue unresolvable" {
  run bash -c "unset WORKER_ISSUE_NUM AUTOPILOT_DIR; cd '$SANDBOX' && (git checkout -b plain-branch 2>/dev/null || true); echo '' | bash scripts/pr-review-manifest.sh --mode merge-gate 2>&1 1>/dev/null"
  assert_success
  assert_output --partial "WARNING: pr-review-manifest"
}

# ===========================================================================
# Requirement: worker-workflow-integrity トリガー (Issue #145, Phase 4-B)
# chain 関連ファイル (deps.yaml / SKILL.md / chain-runner.sh) 変更時のみ追加。
# architecture/*.md 単独変更では起動しない (worker-architecture が担当)。
# ===========================================================================

@test "merge-gate: chain file (deps.yaml) change adds worker-workflow-integrity" {
  run bash -c "echo 'plugins/twl/deps.yaml' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-workflow-integrity"
}

@test "merge-gate: chain file (SKILL.md) change adds worker-workflow-integrity" {
  run bash -c "echo 'plugins/twl/skills/workflow-pr-verify/SKILL.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-workflow-integrity"
}

@test "merge-gate: chain file (chain-runner.sh) change adds worker-workflow-integrity" {
  run bash -c "echo 'plugins/twl/scripts/chain-runner.sh' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-workflow-integrity"
}

@test "merge-gate: architecture-only change does NOT add worker-workflow-integrity" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'architecture/domain/contexts/pr-cycle.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  refute_output --partial "worker-workflow-integrity"
  # worker-architecture は追加されるはず (architecture/ が存在するため)
  assert_output --partial "worker-architecture"
}

@test "merge-gate: unrelated code change does NOT add worker-workflow-integrity" {
  run bash -c "echo 'src/index.ts' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  refute_output --partial "worker-workflow-integrity"
}

@test "merge-gate: chain file + architecture simultaneous change adds BOTH specialists" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "printf 'plugins/twl/deps.yaml\narchitecture/domain/contexts/pr-cycle.md\n' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-workflow-integrity"
  assert_output --partial "worker-architecture"
}

@test "phase-review: chain file change does NOT add worker-workflow-integrity (merge-gate only)" {
  run bash -c "echo 'plugins/twl/deps.yaml' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  refute_output --partial "worker-workflow-integrity"
}
