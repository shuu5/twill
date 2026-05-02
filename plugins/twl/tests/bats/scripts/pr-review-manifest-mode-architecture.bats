#!/usr/bin/env bats
# pr-review-manifest-mode-architecture.bats
# AC A-3: phase-review mode での architecture/ ファイル変更時 worker-architecture 追加テスト
#
# RED テスト: A-3-i, A-3-iv, A-3-v は現状の pr-review-manifest.sh では FAIL する
# PASS テスト: A-3-ii, A-3-iii は現状でも PASS するが、テストとして明示する

load '../helpers/common'

setup() {
  common_setup

  # Create a git repo in sandbox (for PROJECT_ROOT resolution)
  git init "$SANDBOX" 2>/dev/null
  (cd "$SANDBOX" && git commit --allow-empty -m "initial" 2>/dev/null) || true
  export PROJECT_ROOT="$SANDBOX"

  # Default codex stub: "Not logged in"
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
# A-3-i: phase-review + architecture/ 配下ファイル → worker-architecture 含む
# RED: 現状 phase-review では merge-gate only ブロックを通らないため worker-architecture は追加されない
# ===========================================================================

@test "A-3-i: phase-review + architecture/contexts/foo.md → worker-architecture included (RED)" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'architecture/contexts/foo.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-architecture"
}

# ===========================================================================
# A-3-ii: phase-review + FILES = dummy.sh のみ → worker-architecture 含まない
# 現状でもこの動作は成立するが、テストとして明示する
# ===========================================================================

@test "A-3-ii: phase-review + FILES=dummy.sh only → worker-architecture not included" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'dummy.sh' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  refute_output --partial "worker-architecture"
}

# ===========================================================================
# A-3-iii: merge-gate + 任意 FILES → worker-architecture 含む
# architecture/ ディレクトリを事前に作成。現状でも動作するが修正後も維持を確認
# ===========================================================================

@test "A-3-iii: merge-gate + architecture/ dir exists → worker-architecture included" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'dummy.sh' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-architecture"
}

# ===========================================================================
# A-3-iv: phase-review + cli/twl/chain.py 含む → worker-architecture 含む
# RED: 現状 phase-review では worker-architecture は追加されない
# ===========================================================================

@test "A-3-iv: phase-review + cli/twl/chain.py → worker-architecture included (RED)" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'cli/twl/chain.py' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-architecture"
}

# ===========================================================================
# A-3-v: phase-review + plugins/twl/scripts/pr-review-manifest.sh 含む → worker-architecture 含む
# RED: meta-bug 防止確認。現状 phase-review では worker-architecture は追加されない
# ===========================================================================

@test "A-3-v: phase-review + plugins/twl/scripts/pr-review-manifest.sh → worker-architecture included (RED)" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'plugins/twl/scripts/pr-review-manifest.sh' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-architecture"
}

# ===========================================================================
# B-1: phase-review + top-level architecture/foo.md → worker-arch-doc-reviewer 含む
# RED: L184 の */architecture/*.md は先頭に1文字以上を要求するため top-level にマッチしない
#      fix: *architecture/*.md|... に変更すると PASS
# ===========================================================================

@test "B-1: phase-review + top-level architecture/foo.md → worker-arch-doc-reviewer included (RED)" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'architecture/foo.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-arch-doc-reviewer"
}

# ===========================================================================
# B-2: phase-review + nested-1 architecture/contexts/foo.md → worker-arch-doc-reviewer 含む
# RED: L184 の */architecture/*/*.md は先頭に1文字以上を要求するため top-level nested にマッチしない
# ===========================================================================

@test "B-2: phase-review + nested-1 architecture/contexts/foo.md → worker-arch-doc-reviewer included (RED)" {
  mkdir -p "$SANDBOX/architecture/contexts"

  run bash -c "echo 'architecture/contexts/foo.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-arch-doc-reviewer"
}

# ===========================================================================
# B-3: phase-review + nested-2 architecture/decisions/sub/foo.md → worker-arch-doc-reviewer 含む
# RED: L184 の */architecture/*/*/*.md は先頭に1文字以上を要求するため top-level nested-2 にマッチしない
# ===========================================================================

@test "B-3: phase-review + nested-2 architecture/decisions/sub/foo.md → worker-arch-doc-reviewer included (RED)" {
  mkdir -p "$SANDBOX/architecture/decisions/sub"

  run bash -c "echo 'architecture/decisions/sub/foo.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode phase-review"
  assert_success
  assert_output --partial "worker-arch-doc-reviewer"
}

# ===========================================================================
# B-4: merge-gate + top-level architecture/foo.md → worker-arch-doc-reviewer 含む
# RED: L184 の */architecture/*.md は先頭に1文字以上を要求するため top-level にマッチしない
# ===========================================================================

@test "B-4: merge-gate + top-level architecture/foo.md → worker-arch-doc-reviewer included (RED)" {
  mkdir -p "$SANDBOX/architecture"

  run bash -c "echo 'architecture/foo.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-arch-doc-reviewer"
}

# ===========================================================================
# B-5: merge-gate + nested-1 architecture/contexts/foo.md → worker-arch-doc-reviewer 含む
# RED: L184 の */architecture/*/*.md は先頭に1文字以上を要求するため top-level nested にマッチしない
# ===========================================================================

@test "B-5: merge-gate + nested-1 architecture/contexts/foo.md → worker-arch-doc-reviewer included (RED)" {
  mkdir -p "$SANDBOX/architecture/contexts"

  run bash -c "echo 'architecture/contexts/foo.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-arch-doc-reviewer"
}

# ===========================================================================
# B-6: merge-gate + nested-2 architecture/decisions/sub/foo.md → worker-arch-doc-reviewer 含む
# RED: L184 の */architecture/*/*/*.md は先頭に1文字以上を要求するため top-level nested-2 にマッチしない
# ===========================================================================

@test "B-6: merge-gate + nested-2 architecture/decisions/sub/foo.md → worker-arch-doc-reviewer included (RED)" {
  mkdir -p "$SANDBOX/architecture/decisions/sub"

  run bash -c "echo 'architecture/decisions/sub/foo.md' | bash '$SANDBOX/scripts/pr-review-manifest.sh' --mode merge-gate"
  assert_success
  assert_output --partial "worker-arch-doc-reviewer"
}
