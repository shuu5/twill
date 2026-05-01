#!/usr/bin/env bats
# record-detection-gap-deps-registered.bats — Issue #1201 AC 機械的検証テスト（TDD RED フェーズ）
#
# Issue #1201: tech-debt: record-detection-gap.sh を deps.yaml に登録する
#
# このファイルは実装前（RED）状態で全テストが fail することを意図している。
# 実装完了後（GREEN）は全テストが PASS すること。
#
# Coverage:
#   AC1: deps.yaml に record-detection-gap entry が存在する（type, path, description の 3 フィールド）
#   AC2: loom check が Missing: 0 で PASS する
#   AC3: このテストファイル自体が存在し、deps.yaml の record-detection-gap entry + path フィールドを assert する SSoT 完備性テスト
#   AC4: twl check --deps-integrity（pre-commit hook 相当）が PASS する

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: deps.yaml に record-detection-gap component entry が追加されている
# RED 理由: 現在 plugins/twl/deps.yaml に record-detection-gap エントリが存在しないため fail する
# ===========================================================================

@test "ac1: deps.yaml に record-detection-gap エントリが存在する" {
  # AC: plugins/twl/deps.yaml に record-detection-gap.sh の component entry を追加する
  local deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が見つからない: $deps_yaml"

  # RED: record-detection-gap エントリが未追加のため fail する
  grep -q "record-detection-gap:" "$deps_yaml" \
    || fail "deps.yaml に 'record-detection-gap:' エントリがない（AC1 未達 — entry 追加が必要）"
}

@test "ac1: deps.yaml の record-detection-gap エントリに type フィールドがある" {
  # AC: 3 フィールドのみ（type, path, description）
  local deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が見つからない: $deps_yaml"

  # RED: record-detection-gap エントリが未追加のため、type フィールドの確認も fail する
  grep -A5 "record-detection-gap:" "$deps_yaml" | grep -q "type:" \
    || fail "deps.yaml の record-detection-gap エントリに 'type:' フィールドがない（AC1 未達）"
}

@test "ac1: deps.yaml の record-detection-gap エントリに path フィールドがある" {
  # AC: 3 フィールドのみ（type, path, description）
  local deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が見つからない: $deps_yaml"

  # RED: record-detection-gap エントリが未追加のため fail する
  grep -A5 "record-detection-gap:" "$deps_yaml" | grep -q "path:" \
    || fail "deps.yaml の record-detection-gap エントリに 'path:' フィールドがない（AC1 未達）"
}

@test "ac1: deps.yaml の record-detection-gap エントリに description フィールドがある" {
  # AC: 3 フィールドのみ（type, path, description）
  local deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が見つからない: $deps_yaml"

  # RED: record-detection-gap エントリが未追加のため fail する
  grep -A5 "record-detection-gap:" "$deps_yaml" | grep -q "description:" \
    || fail "deps.yaml の record-detection-gap エントリに 'description:' フィールドがない（AC1 未達）"
}

@test "ac1: deps.yaml の record-detection-gap path が skills/su-observer/scripts/record-detection-gap.sh を指している" {
  # AC: spawn-controller.sh と同パターン。実体は skills/su-observer/scripts/ 配下
  local deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が見つからない: $deps_yaml"

  # RED: エントリが未追加のため fail する
  grep -A5 "record-detection-gap:" "$deps_yaml" \
    | grep -q "skills/su-observer/scripts/record-detection-gap.sh" \
    || fail "deps.yaml の record-detection-gap.path が 'skills/su-observer/scripts/record-detection-gap.sh' を指していない（AC1 未達）"
}

# ===========================================================================
# AC2: loom check が SSoT 完備性 Missing: 0 で PASS する
# RED 理由: record-detection-gap エントリが deps.yaml に未登録のため Missing > 0 になる
# ===========================================================================

@test "ac2: loom check が Missing: 0 で PASS する（SSoT 完備性）" {
  # AC: loom check を実行し、deps.yaml の SSoT 完備性（Missing: 0）が PASS する
  # RED: record-detection-gap が deps.yaml 未登録のため Missing > 0 で fail する

  if ! command -v loom &>/dev/null; then
    skip "loom コマンドが見つからない（CI 環境では skip）"
  fi

  local output
  output=$(cd "$REPO_ROOT" && loom check 2>&1)
  local exit_code=$?

  # Missing: 0 が含まれること
  echo "$output" | grep -qE "Missing:\s*0" \
    || fail "loom check で Missing ファイルが検出された（AC2 未達 — record-detection-gap を deps.yaml に追加してから再実行）: $output"

  [[ "$exit_code" -eq 0 ]] \
    || fail "loom check が非ゼロ終了した（AC2 未達）: $output"
}

# ===========================================================================
# AC3: このテストファイルが存在し、deps.yaml の SSoT 完備性テストを担う
# AC3 の「bats test ファイルを追加する」という AC に対して:
#   - このファイル自体の存在確認
#   - deps.yaml の record-detection-gap entry 存在 + path フィールド正当性を assert（上記 AC1 テストで担保）
# RED 理由: AC1 テストが依存する deps.yaml エントリが存在しないため、構造的に fail する
# ===========================================================================

@test "ac3: record-detection-gap-deps-registered.bats ファイルが存在する（SSoT 完備性テスト配置確認）" {
  # AC: bats test を追加する（plugins/twl/tests/bats/scripts/record-detection-gap-deps-registered.bats）
  local test_file="$REPO_ROOT/tests/bats/scripts/record-detection-gap-deps-registered.bats"

  [[ -f "$test_file" ]] \
    || fail "record-detection-gap-deps-registered.bats が存在しない: $test_file（AC3 未達 — テストファイル配置が必要）"
}

@test "ac3: bats テストが deps.yaml の record-detection-gap entry 存在を assert する（SSoT 完備性テスト機能確認）" {
  # AC: deps.yaml を grep し、record-detection-gap.sh entry の存在 + path フィールドが正しいことを assert する
  # このテストは "テストが機能的に deps.yaml SSoT 完備性を検証できる構造にある" ことを確認する
  local test_file="$REPO_ROOT/tests/bats/scripts/record-detection-gap-deps-registered.bats"

  [[ -f "$test_file" ]] \
    || fail "record-detection-gap-deps-registered.bats が存在しない: $test_file"

  # テストファイルが deps.yaml の record-detection-gap を grep していること
  grep -q "record-detection-gap" "$test_file" \
    || fail "record-detection-gap-deps-registered.bats が deps.yaml の record-detection-gap entry を参照していない（AC3 未達）"

  # テストファイルが path フィールドを検証していること
  grep -q "path" "$test_file" \
    || fail "record-detection-gap-deps-registered.bats が path フィールド検証を含んでいない（AC3 未達）"
}

# ===========================================================================
# AC4: pre-commit hook（twl check --deps-integrity）が PASS する
# RED 理由: deps.yaml に record-detection-gap エントリが未登録のため、
#           deps-integrity チェック（SSoT 完備性）が失敗する可能性がある
# ===========================================================================

@test "ac4: twl check --deps-integrity が 0 errors で PASS する" {
  # AC: bash plugins/twl/scripts/install-git-hooks.sh 配下の pre-commit hook が PASS する
  # RED: record-detection-gap が deps.yaml に未登録 → deps-integrity check が失敗する場合 fail

  if ! command -v twl &>/dev/null; then
    skip "twl コマンドが見つからない（CI 環境では skip）"
  fi

  local output
  output=$(cd "$REPO_ROOT" && twl check --deps-integrity 2>&1)
  local exit_code=$?

  [[ "$exit_code" -eq 0 ]] \
    || fail "twl check --deps-integrity が失敗した（AC4 未達 — record-detection-gap を deps.yaml に追加してから再実行）: $output"
}

@test "ac4: git-pre-commit-deps-integrity.sh が実行可能ファイルとして存在する" {
  # pre-commit hook の実体が存在し実行可能であること
  local hook_src="$REPO_ROOT/scripts/hooks/git-pre-commit-deps-integrity.sh"

  [[ -f "$hook_src" ]] \
    || fail "git-pre-commit-deps-integrity.sh が見つからない: $hook_src（AC4 前提条件）"

  [[ -x "$hook_src" ]] \
    || fail "git-pre-commit-deps-integrity.sh が実行可能でない: $hook_src（AC4 前提条件）"
}
