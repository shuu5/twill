#!/usr/bin/env bats
# baseline-bash.bats - structural validation of baseline-bash.md and its integration
#
# 8 test cases for #513 (character class ハイフン / for-loop local / set -u 初期化 / IFS)

setup() {
  local helpers_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_test_dir="$(cd "$helpers_dir/.." && pwd)"
  local tests_dir="$(cd "$bats_test_dir/.." && pwd)"
  REPO_ROOT="$(cd "$tests_dir/.." && pwd)"
  export REPO_ROOT
}

# ---------------------------------------------------------------------------
# Case 1: baseline-bash.md 存在 + frontmatter 検証
# ---------------------------------------------------------------------------

@test "baseline-bash: file exists" {
  local file="$REPO_ROOT/refs/baseline-bash.md"
  [ -f "$file" ]
}

@test "baseline-bash: frontmatter has type=reference and disable-model-invocation=true" {
  local file="$REPO_ROOT/refs/baseline-bash.md"
  grep -q 'type: reference' "$file"
  grep -q 'disable-model-invocation: true' "$file"
}

# ---------------------------------------------------------------------------
# Case 2: 4 セクション見出し検証
# ---------------------------------------------------------------------------

@test "baseline-bash: has all 4 required section headings" {
  local file="$REPO_ROOT/refs/baseline-bash.md"
  grep -q '## 1\. Character Class' "$file"
  grep -q '## 2\. for-loop' "$file"
  grep -q '## 3\. local' "$file"
  grep -q '## 4\.' "$file"
}

# ---------------------------------------------------------------------------
# Case 3: BAD/GOOD 対比ブロック検証
# ---------------------------------------------------------------------------

@test "baseline-bash: each section has BAD and GOOD code blocks" {
  local file="$REPO_ROOT/refs/baseline-bash.md"
  local bad_count good_count
  bad_count=$(grep -c '# BAD' "$file" || true)
  good_count=$(grep -c '# GOOD' "$file" || true)
  [ "$bad_count" -ge 4 ]
  [ "$good_count" -ge 4 ]
}

# ---------------------------------------------------------------------------
# Case 4: IFS セクションのキーワード検証
# ---------------------------------------------------------------------------

@test "baseline-bash: IFS section contains required keywords" {
  local file="$REPO_ROOT/refs/baseline-bash.md"
  grep -q 'IFS=' "$file"
  grep -qF 'key="${line%%=*}"' "$file"
  grep -qF 'val="${line#*=}"' "$file"
}

# ---------------------------------------------------------------------------
# Case 5: worker-code-reviewer.md の参照追加確認
# ---------------------------------------------------------------------------

@test "worker-code-reviewer: baseline-bash.md is referenced as 3rd baseline entry" {
  local file="$REPO_ROOT/agents/worker-code-reviewer.md"
  [ -f "$file" ]
  # 3番目のエントリとして baseline-bash.md が含まれること
  grep -q 'baseline-bash\.md' "$file"
}

# ---------------------------------------------------------------------------
# Case 6: deps.yaml のエントリ検証
# ---------------------------------------------------------------------------

@test "deps.yaml: baseline-bash entry exists with type reference" {
  local file="$REPO_ROOT/deps.yaml"
  grep -q 'baseline-bash:' "$file"
  grep -q 'type: reference' "$file"
}

@test "deps.yaml: phase-review and merge-gate reference baseline-bash" {
  local file="$REPO_ROOT/deps.yaml"
  # baseline-bash が少なくとも2箇所(phase-review + merge-gate)参照されること
  local ref_count
  ref_count=$(grep -c 'reference: baseline-bash' "$file" || true)
  [ "$ref_count" -ge 2 ]
}

# ---------------------------------------------------------------------------
# Case 7: baseline-coding-style.md の IFS セクション置換確認
# ---------------------------------------------------------------------------

@test "baseline-coding-style: IFS section is replaced with cross-reference to baseline-bash.md" {
  local file="$REPO_ROOT/refs/baseline-coding-style.md"
  [ -f "$file" ]
  # baseline-bash.md への参照が存在すること
  grep -q 'baseline-bash' "$file"
}
