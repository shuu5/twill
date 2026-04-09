#!/usr/bin/env bats
# observer-evaluator-parser.bats - parser script の検証 (5 test cases)

load '../helpers/common'

setup() {
  common_setup
  PARSER="$REPO_ROOT/scripts/observer-evaluator-parser.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# 1. 正常系: 全評価に quote あり, confidence<=75 → そのまま通過
# ---------------------------------------------------------------------------

@test "parser passes valid JSON with quotes and confidence<=75 unchanged" {
  cat > "$SANDBOX/valid.json" <<'JSON'
{
  "specialist": "observer-evaluator",
  "model": "sonnet",
  "input_window": "ap-42",
  "rule_based_count": 2,
  "llm_evaluations": [
    {
      "type": "severity-adjust",
      "rule_pattern": "MergeGateError",
      "original_severity": "high",
      "adjusted_severity": "critical",
      "reason": "base drift with deleted files",
      "quote": "MergeGateError: base drift detected: deleted_files=[config.yaml]",
      "confidence": 75
    },
    {
      "type": "new-finding",
      "category": "worker-prompt-redundancy",
      "description": "Worker repeats verify 3 times",
      "quote": "verify step at line 23, 47, 89",
      "confidence": 60
    }
  ],
  "root_cause_candidates": [
    {
      "cause": "stale branch",
      "evidence_quote": "last rebase was 3 days ago",
      "confidence": 70
    }
  ],
  "improvement_suggestions": [
    "Add rebase check before merge gate"
  ],
  "summary": "2 evaluations, 1 root cause candidate"
}
JSON

  run bash "$PARSER" "$SANDBOX/valid.json"

  assert_success

  # llm_evaluations should still have 2 entries
  EVAL_COUNT="$(echo "$output" | jq '.llm_evaluations | length')"
  [[ "$EVAL_COUNT" -eq 2 ]]

  # warnings should be empty
  WARN_COUNT="$(echo "$output" | jq '.warnings | length')"
  [[ "$WARN_COUNT" -eq 0 ]]

  # confidence values should be unchanged
  CONF1="$(echo "$output" | jq '.llm_evaluations[0].confidence')"
  CONF2="$(echo "$output" | jq '.llm_evaluations[1].confidence')"
  [[ "$CONF1" -eq 75 ]]
  [[ "$CONF2" -eq 60 ]]
}

# ---------------------------------------------------------------------------
# 2. 引用なし降格: quote 空の評価が warnings 配列に移動
# ---------------------------------------------------------------------------

@test "parser demotes evaluations with missing quote to warnings" {
  cat > "$SANDBOX/missing-quote.json" <<'JSON'
{
  "specialist": "observer-evaluator",
  "model": "sonnet",
  "input_window": "ap-42",
  "rule_based_count": 1,
  "llm_evaluations": [
    {
      "type": "severity-adjust",
      "rule_pattern": "MergeGateError",
      "original_severity": "high",
      "adjusted_severity": "critical",
      "reason": "base drift",
      "quote": "MergeGateError: base drift detected",
      "confidence": 70
    },
    {
      "type": "new-finding",
      "category": "redundant-verify",
      "description": "Worker repeats verify",
      "quote": "",
      "confidence": 60
    },
    {
      "type": "new-finding",
      "category": "stalled-phase",
      "description": "Phase seems stalled",
      "confidence": 50
    }
  ],
  "summary": "3 evaluations, 2 without valid quote"
}
JSON

  run bash "$PARSER" "$SANDBOX/missing-quote.json"

  assert_success

  # Only 1 evaluation should remain (the one with a valid quote)
  EVAL_COUNT="$(echo "$output" | jq '.llm_evaluations | length')"
  [[ "$EVAL_COUNT" -eq 1 ]]

  # 2 evaluations should be in warnings
  WARN_COUNT="$(echo "$output" | jq '.warnings | length')"
  [[ "$WARN_COUNT" -eq 2 ]]

  # Warnings should have demotion reason
  REASON="$(echo "$output" | jq -r '.warnings[0].demoted_reason')"
  [[ "$REASON" == "quote field missing or empty" ]]
}

# ---------------------------------------------------------------------------
# 3. confidence クランプ: confidence=90 が 75 にクランプ
# ---------------------------------------------------------------------------

@test "parser clamps confidence > 75 to 75" {
  cat > "$SANDBOX/high-confidence.json" <<'JSON'
{
  "specialist": "observer-evaluator",
  "model": "sonnet",
  "input_window": "ap-42",
  "rule_based_count": 1,
  "llm_evaluations": [
    {
      "type": "severity-adjust",
      "rule_pattern": "Error",
      "original_severity": "high",
      "adjusted_severity": "critical",
      "reason": "critical error",
      "quote": "Error: critical failure detected",
      "confidence": 90
    }
  ],
  "root_cause_candidates": [
    {
      "cause": "stale branch",
      "evidence_quote": "last rebase 3 days ago",
      "confidence": 85
    }
  ],
  "summary": "confidence over 75 test"
}
JSON

  run bash "$PARSER" "$SANDBOX/high-confidence.json"

  assert_success

  # llm_evaluations confidence should be clamped to 75
  CONF="$(echo "$output" | jq '.llm_evaluations[0].confidence')"
  [[ "$CONF" -eq 75 ]]

  # root_cause_candidates confidence should also be clamped to 75
  RC_CONF="$(echo "$output" | jq '.root_cause_candidates[0].confidence')"
  [[ "$RC_CONF" -eq 75 ]]
}

# ---------------------------------------------------------------------------
# 4. malformed JSON: 不正 JSON 入力で exit 1
# ---------------------------------------------------------------------------

@test "parser exits 1 on malformed JSON" {
  echo "this is not json {{{" > "$SANDBOX/bad.json"

  run bash "$PARSER" "$SANDBOX/bad.json"

  assert_failure
  assert_output --partial "malformed JSON"
}

# ---------------------------------------------------------------------------
# 5. 必須フィールド欠落: summary 欠落で exit 1
# ---------------------------------------------------------------------------

@test "parser exits 1 when required field summary is missing" {
  cat > "$SANDBOX/no-summary.json" <<'JSON'
{
  "specialist": "observer-evaluator",
  "llm_evaluations": []
}
JSON

  run bash "$PARSER" "$SANDBOX/no-summary.json"

  assert_failure
  assert_output --partial "missing required fields"
  assert_output --partial "summary"
}
