#!/usr/bin/env bats
# specialist-audit.bats - unit tests for scripts/specialist-audit.sh
# Generated from: deltaspec/changes/issue-745/specs/bats-specialist-audit.md
# Requirement: specialist-audit BATS テスト追加
# Coverage: unit + edge-cases

load '../helpers/common'

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# create_mock_jsonl <path> <specialist_names...>
# JSONL を作成。各 specialist 名は "twl:twl:worker-<name>" の subagent_type エントリ付き行として記録
create_mock_jsonl() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  # header line: Issue reference
  printf '{"type":"message","content":"Issue #999 test"}\n' > "$path"
  for sp in "$@"; do
    printf '{"type":"tool_use","subagent_type":"twl:twl:worker-%s"}\n' "$sp" >> "$path"
  done
}

# create_mock_manifest <path> <specialist_names...>
# pr-review-manifest 出力を模したファイル（twl:twl: プレフィックスなし形式）
create_mock_manifest() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  > "$path"
  for sp in "$@"; do
    printf 'worker-%s\n' "$sp" >> "$path"
  done
}

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  # pr-review-manifest.sh をスタブ化（デフォルトは空リスト = expected 空）
  stub_command "pr-review-manifest.sh" 'exit 0'
  # jq はシステム jq をそのまま使用
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: specialist-audit BATS テスト追加
# ---------------------------------------------------------------------------

@test "specialist-audit.sh が存在する" {
  [[ -f "$SANDBOX/scripts/specialist-audit.sh" ]]
}

@test "specialist-audit.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/specialist-audit.sh" ]]
}

@test "specialist-audit.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/specialist-audit.sh"
}

# ---------------------------------------------------------------------------
# Scenario: PASS ケース（expected ⊆ actual）
# WHEN: expected が actual の部分集合であるケースで specialist-audit.sh を実行する
# THEN: exit 0 を返し、JSON 出力の .status が "PASS" である
# ---------------------------------------------------------------------------

@test "PASS ケース: expected が actual の部分集合の場合 exit 0 を返す" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer" "security-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
}

@test "PASS ケース: expected が actual の部分集合の場合 .status が PASS になる" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer" "security-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e '.status == "PASS"' > /dev/null
}

@test "PASS ケース: missing が空の場合 JSON に missing 空配列が含まれる" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e '.missing | length == 0' > /dev/null
}

# ---------------------------------------------------------------------------
# Scenario: FAIL ケース（warn-only モード）
# WHEN: missing が非空かつ --warn-only フラグを指定して実行する
# THEN: exit 0 を返し、JSON 出力の .status が "FAIL" である
# ---------------------------------------------------------------------------

@test "warn-only: missing 非空 + --warn-only で exit 0 を返す" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    --warn-only

  assert_success
}

@test "warn-only: missing 非空 + --warn-only で .status が FAIL になる" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  run --separate-stderr bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    --warn-only

  assert_success
  echo "$output" | jq -e '.status == "FAIL"' > /dev/null
}

@test "warn-only: .missing に不足 specialist 名が含まれる" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  run --separate-stderr bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    --warn-only

  assert_success
  echo "$output" | jq -e '.missing | map(select(. == "worker-security-reviewer")) | length == 1' > /dev/null
}

# ---------------------------------------------------------------------------
# Scenario: FAIL ケース（strict モード）
# WHEN: missing が非空かつフラグなし（strict = default）で実行する
# THEN: exit 1 を返す
# ---------------------------------------------------------------------------

@test "strict モード: missing 非空 + SPECIALIST_AUDIT_MODE=strict で exit 1 を返す" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  SPECIALIST_AUDIT_MODE=strict \
  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_failure
}

@test "strict モード: missing 非空 + SPECIALIST_AUDIT_MODE=strict で .status が FAIL になる" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  SPECIALIST_AUDIT_MODE=strict \
  run --separate-stderr bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  # exit 1 かつ JSON に status=FAIL が含まれる
  assert_failure
  echo "$output" | jq -e '.status == "FAIL"' > /dev/null
}

# ---------------------------------------------------------------------------
# Scenario: quick モード
# WHEN: missing が非空かつ --quick フラグを指定して実行する
# THEN: exit 0 を返す（WARN のみ）
# ---------------------------------------------------------------------------

@test "quick モード: missing 非空 + --quick で exit 0 を返す" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  SPECIALIST_AUDIT_MODE=strict \
  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    --quick

  assert_success
}

@test "quick モード: missing 非空 + --quick で .status が WARN になる" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  SPECIALIST_AUDIT_MODE=strict \
  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    --quick

  assert_success
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
}

# ---------------------------------------------------------------------------
# Scenario: JSON 出力構造契約
# WHEN: specialist-audit.sh をデフォルトモードで実行する
# THEN: 出力が jq でパース可能かつ .status, .missing, .actual, .expected キーを含む
#       SKILL.md の grep -q '"status":"FAIL"' がこの出力に対して成立する契約の機械的固定
# ---------------------------------------------------------------------------

@test "JSON 構造契約: 出力が jq でパース可能である" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq '.' > /dev/null
}

@test "JSON 構造契約: .status キーが存在する" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e 'has("status")' > /dev/null
}

@test "JSON 構造契約: .missing キーが存在する" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e 'has("missing")' > /dev/null
}

@test "JSON 構造契約: .actual キーが存在する" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e 'has("actual")' > /dev/null
}

@test "JSON 構造契約: .expected キーが存在する" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e 'has("expected")' > /dev/null
}

@test "JSON 構造契約: FAIL 状態の出力に grep -q '\"status\":\"FAIL\"' が反応する" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer" "security-reviewer"

  # --warn-only: exit 0 だが JSON に "status":"FAIL" が含まれる
  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    --warn-only

  assert_success
  # SKILL.md の grep 契約を機械的に検証
  echo "$output" | grep -q '"status":"FAIL"'
}

@test "JSON 構造契約: PASS 状態の出力に grep -q '\"status\":\"FAIL\"' が反応しない" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  # PASS の場合は "status":"FAIL" が含まれてはならない
  run grep -q '"status":"FAIL"' <<< "$output"
  assert_failure
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "edge: --issue と --jsonl の同時指定はエラー" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  create_mock_jsonl "$jsonl" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --issue 123 \
    --jsonl "$jsonl"

  assert_failure
}

@test "edge: 引数なしは exit 1" {
  run bash "$SANDBOX/scripts/specialist-audit.sh"
  assert_failure
}

@test "edge: --issue に数値以外を渡すとエラー" {
  run bash "$SANDBOX/scripts/specialist-audit.sh" --issue "../../etc/passwd"
  assert_failure
  assert_output --partial "数値"
}

@test "edge: SKIP_SPECIALIST_AUDIT=1 で exit 0 かつ SKIP JSON を出力する" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  create_mock_jsonl "$jsonl" "code-reviewer"

  SKIP_SPECIALIST_AUDIT=1 \
  run --separate-stderr bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl"

  assert_success
  echo "$output" | jq -e '.status == "SKIP"' > /dev/null
}

@test "edge: JSONL が存在しない場合は WARN JSON を exit 0 で出力する" {
  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$SANDBOX/nonexistent.jsonl"

  assert_success
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
}

@test "edge: 空の manifest と空の JSONL で PASS を返す" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  # JSONL に subagent_type なし（header 行のみ）
  mkdir -p "$(dirname "$jsonl")"
  printf '{"type":"message","content":"Issue #999 test"}\n' > "$jsonl"
  # manifest も空
  > "$manifest"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e '.status == "PASS"' > /dev/null
}

@test "edge: extra（manifest にない）specialist は .extra に記録される" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  create_mock_jsonl "$jsonl" "code-reviewer" "extra-specialist"
  create_mock_manifest "$manifest" "code-reviewer"

  run bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest"

  assert_success
  echo "$output" | jq -e '.extra | map(select(. == "worker-extra-specialist")) | length == 1' > /dev/null
}
