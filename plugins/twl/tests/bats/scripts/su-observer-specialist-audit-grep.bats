#!/usr/bin/env bats
# su-observer-specialist-audit-grep.bats - SKILL.md grep 契約の機械的固定テスト
# Generated from: deltaspec/changes/issue-745/specs/bats-specialist-audit.md
# Requirement: grep 契約ロック BATS テスト追加 / SKILL.md 回帰防止（--summary 非使用維持）
# Coverage: unit + edge-cases

load '../helpers/common'

setup() {
  common_setup
  # テスト用 audit ディレクトリをサンドボックス内に作成
  WAVE_N="wave-1"
  AUDIT_DIR="$SANDBOX/.audit/$WAVE_N"
  AUDIT_LOG="$AUDIT_DIR/specialist-audit.log"
  mkdir -p "$AUDIT_DIR"
  export WAVE_N AUDIT_DIR AUDIT_LOG
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: grep 契約ロック BATS テスト追加
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Scenario: FAIL 含有 JSONL に grep が反応する
# WHEN: .audit/wave-N/specialist-audit.log にモック JSONL（"status":"FAIL" を含む JSON 行）を書き込む
# THEN: grep -q '"status":"FAIL"' .audit/wave-N/specialist-audit.log が exit 0 を返す
# ---------------------------------------------------------------------------

@test "grep 契約: FAIL 含有ログに grep -q '\"status\":\"FAIL\"' が exit 0 を返す" {
  printf '{"status":"FAIL","issue":123,"missing":["security-reviewer"],"actual":["code-reviewer"],"expected":["code-reviewer","security-reviewer"]}\n' \
    > "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_success
}

@test "grep 契約: 複数行のうち1行に FAIL がある場合 exit 0 を返す" {
  printf '{"status":"PASS","issue":100,"missing":[],"actual":["code-reviewer"],"expected":["code-reviewer"]}\n' \
    > "$AUDIT_LOG"
  printf '{"status":"FAIL","issue":101,"missing":["security-reviewer"],"actual":[],"expected":["security-reviewer"]}\n' \
    >> "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_success
}

@test "grep 契約: WARN 状態（warn-only モード出力）のログにも FAIL が含まれる場合 exit 0 を返す" {
  # specialist-audit.sh --warn-only は FAIL status を JSON に出力する（exit 0 でも .status=FAIL）
  printf '{"status":"FAIL","issue":200,"missing":["doc-reviewer"],"actual":[],"expected":["doc-reviewer"],"audit_mode":"warn"}\n' \
    > "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: PASS のみ JSONL に grep が反応しない
# WHEN: .audit/wave-N/specialist-audit.log にモック JSONL（"status":"PASS" のみの JSON 行）を書き込む
# THEN: grep -q '"status":"FAIL"' .audit/wave-N/specialist-audit.log が exit 1 を返す
# ---------------------------------------------------------------------------

@test "grep 契約: PASS のみのログに grep -q '\"status\":\"FAIL\"' が exit 1 を返す" {
  printf '{"status":"PASS","issue":123,"missing":[],"actual":["code-reviewer"],"expected":["code-reviewer"]}\n' \
    > "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_failure
}

@test "grep 契約: 複数 PASS 行のログに exit 1 を返す" {
  printf '{"status":"PASS","issue":100,"missing":[],"actual":["code-reviewer"],"expected":["code-reviewer"]}\n' \
    > "$AUDIT_LOG"
  printf '{"status":"PASS","issue":101,"missing":[],"actual":["security-reviewer"],"expected":["security-reviewer"]}\n' \
    >> "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_failure
}

@test "grep 契約: WARN status はマッチしない" {
  printf '{"status":"WARN","issue":300,"missing":[],"actual":[],"expected":[]}\n' \
    > "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_failure
}

@test "grep 契約: SKIP status はマッチしない" {
  printf '{"status":"SKIP","reason":"SKIP_SPECIALIST_AUDIT=1"}\n' \
    > "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_failure
}

@test "grep 契約: ログが空の場合は exit 1 を返す" {
  > "$AUDIT_LOG"

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"

  assert_failure
}

# ---------------------------------------------------------------------------
# Requirement: SKILL.md 回帰防止（--summary 非使用維持）
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Scenario: --summary が実行コードとして使われていない
# WHEN: sed -n '/for issue_json in/,/WARN: specialist-audit/p' ... | grep -v '^[[:space:]]*#' | grep -- '--summary'
# THEN: exit 1 を返す（マッチなし）
# ---------------------------------------------------------------------------

@test "SKILL.md 回帰防止: su-observer/SKILL.md の for issue_json ブロックに --summary が実行コードとして含まれていない" {
  local skill_md="$REPO_ROOT/skills/su-observer/SKILL.md"

  # SKILL.md が存在することを確認
  [[ -f "$skill_md" ]]

  # for issue_json ブロック内のコメントを除いた行に --summary が含まれないことを確認
  run bash -c "
    sed -n '/for issue_json in/,/WARN: specialist-audit/p' '$skill_md' \
      | grep -v '^[[:space:]]*#' \
      | grep -- '--summary'
  "

  # --summary が見つかれば exit 0（=テスト失敗）、見つからなければ exit 1（=テスト成功）
  assert_failure
}

@test "SKILL.md 回帰防止: grep パターンが '\"status\":\"FAIL\"' を使用している" {
  local skill_md="$REPO_ROOT/skills/su-observer/SKILL.md"

  [[ -f "$skill_md" ]]

  # SKILL.md の for issue_json ブロックに '"status":"FAIL"' grep パターンが含まれる
  run bash -c "
    sed -n '/for issue_json in/,/WARN: specialist-audit/p' '$skill_md' \
      | grep -q '\"status\":\"FAIL\"'
  "

  assert_success
}

@test "SKILL.md 回帰防止: --warn-only フラグが for ブロック内に存在する（bootstrapping 設計の維持）" {
  local skill_md="$REPO_ROOT/skills/su-observer/SKILL.md"

  [[ -f "$skill_md" ]]

  run bash -c "
    sed -n '/for issue_json in/,/WARN: specialist-audit/p' '$skill_md' \
      | grep -v '^[[:space:]]*#' \
      | grep -q -- '--warn-only'
  "

  assert_success
}

# ---------------------------------------------------------------------------
# Integration: specialist-audit.sh の実出力がgrep契約に適合する
# ---------------------------------------------------------------------------

@test "integration: FAIL 出力を --warn-only で得たログに grep 契約が成立する" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  # JSONL: code-reviewer のみ
  mkdir -p "$(dirname "$jsonl")"
  printf '{"type":"message","content":"Issue #999 test"}\n' > "$jsonl"
  printf '{"type":"tool_use","subagent_type":"twl:twl:worker-code-reviewer"}\n' >> "$jsonl"

  # manifest: code-reviewer + security-reviewer (missing: security-reviewer)
  printf 'code-reviewer\n' > "$manifest"
  printf 'security-reviewer\n' >> "$manifest"

  # specialist-audit.sh の出力を AUDIT_LOG に追記
  SPECIALIST_AUDIT_MODE=warn \
  bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    --warn-only \
    >> "$AUDIT_LOG" 2>&1 || true

  # grep 契約の検証
  run grep -q '"status":"FAIL"' "$AUDIT_LOG"
  assert_success
}

@test "integration: PASS 出力を得たログに grep 契約が不反応になる" {
  local jsonl="$SANDBOX/.claude/projects/test/test.jsonl"
  local manifest="$SANDBOX/manifest.txt"

  # JSONL: code-reviewer あり
  mkdir -p "$(dirname "$jsonl")"
  printf '{"type":"message","content":"Issue #999 test"}\n' > "$jsonl"
  printf '{"type":"tool_use","subagent_type":"twl:twl:worker-code-reviewer"}\n' >> "$jsonl"

  # manifest: code-reviewer のみ（全 expected が actual に存在）
  printf 'code-reviewer\n' > "$manifest"

  bash "$SANDBOX/scripts/specialist-audit.sh" \
    --jsonl "$jsonl" \
    --manifest-file "$manifest" \
    >> "$AUDIT_LOG" 2>&1 || true

  run grep -q '"status":"FAIL"' "$AUDIT_LOG"
  assert_failure
}
