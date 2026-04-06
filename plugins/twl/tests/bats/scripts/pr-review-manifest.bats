#!/usr/bin/env bats
# pr-review-manifest.bats - unit tests for scripts/pr-review-manifest.sh

load '../helpers/common'

setup() {
  common_setup

  # Create a git repo in sandbox (for PROJECT_ROOT resolution)
  git init "$SANDBOX" 2>/dev/null
  (cd "$SANDBOX" && git commit --allow-empty -m "initial" 2>/dev/null) || true
  export PROJECT_ROOT="$SANDBOX"
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

@test "post-fix-verify excludes codex when CODEX_API_KEY is unset" {
  # Create a fake codex command in stub bin
  cat > "$STUB_BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB_BIN/codex"

  run bash -c "unset CODEX_API_KEY; echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
  assert_success
  refute_output --partial "worker-codex-reviewer"
}

@test "post-fix-verify includes codex when codex command and CODEX_API_KEY exist" {
  cat > "$STUB_BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB_BIN/codex"

  run bash -c "export CODEX_API_KEY=testkey; echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode post-fix-verify"
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

@test "phase-review: no code change returns empty output" {
  run bash -c "echo 'README.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output ""
}

@test "phase-review: empty input returns empty output" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
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
