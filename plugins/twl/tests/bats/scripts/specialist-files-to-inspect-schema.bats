#!/usr/bin/env bats
# specialist-files-to-inspect-schema.bats
# AC4: files_to_inspect フィールドありの fixture と無しの fixture の双方が
#      jq でパース可能かを検証する。

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC4: files_to_inspect あり fixture の jq パース検証
# ---------------------------------------------------------------------------

@test "ac4: specialist output with files_to_inspect parses successfully with jq" {
  # AC: files_to_inspect フィールドありの出力が parse 可能
  # この JSON 形式は AC2 で定義された出力形式
  local fixture
  fixture=$(cat <<'EOF'
{
  "status": "WARN",
  "files_to_inspect": [
    "plugins/twl/agents/worker-architecture.md",
    "plugins/twl/agents/worker-workflow-integrity.md",
    "plugins/twl/agents/context-checker.md"
  ],
  "findings": [
    {
      "severity": "WARNING",
      "confidence": 70,
      "file": "plugins/twl/agents/worker-architecture.md",
      "line": 114,
      "message": "出力形式節に files_to_inspect が未記載",
      "category": "architecture-drift"
    }
  ]
}
EOF
)

  run bash -c "echo '$fixture' | jq -e '.status == \"WARN\"'"
  assert_success

  run bash -c "echo '$fixture' | jq -e '.files_to_inspect | type == \"array\"'"
  assert_success

  run bash -c "echo '$fixture' | jq -e '.files_to_inspect | length == 3'"
  assert_success

  run bash -c "echo '$fixture' | jq -e '.findings | length == 1'"
  assert_success
}

@test "ac4: files_to_inspect array contains relative paths (strings)" {
  # AC: files_to_inspect は相対パス配列（string[]）
  local fixture
  fixture=$(cat <<'EOF'
{
  "status": "FAIL",
  "files_to_inspect": [
    "plugins/twl/agents/worker-architecture.md",
    "plugins/twl/refs/ref-specialist-output-schema.md"
  ],
  "findings": [
    {
      "severity": "CRITICAL",
      "confidence": 90,
      "file": "plugins/twl/agents/worker-architecture.md",
      "line": 1,
      "message": "test finding",
      "category": "architecture-drift"
    }
  ]
}
EOF
)

  run bash -c "echo '$fixture' | jq -e '[.files_to_inspect[] | type == \"string\"] | all'"
  assert_success
}

# ---------------------------------------------------------------------------
# AC4: files_to_inspect なし fixture の jq パース検証（後方互換）
# ---------------------------------------------------------------------------

@test "ac4: specialist output without files_to_inspect parses successfully with jq" {
  # AC: files_to_inspect は optional（省略時は空配列扱い）
  # 省略した出力が従来通りパース可能であること（後方互換）
  local fixture
  fixture=$(cat <<'EOF'
{
  "status": "PASS",
  "findings": []
}
EOF
)

  run bash -c "echo '$fixture' | jq -e '.status == \"PASS\"'"
  assert_success

  run bash -c "echo '$fixture' | jq -e '.findings == []'"
  assert_success

  # files_to_inspect が省略された場合は null として扱われる（空配列扱い）
  run bash -c "echo '$fixture' | jq -e '(.files_to_inspect // []) | type == \"array\"'"
  assert_success
}

@test "ac4: files_to_inspect omitted output has empty array via default" {
  # AC: files_to_inspect 省略時は空配列扱い（// [] でフォールバック）
  local fixture='{"status":"PASS","findings":[]}'

  run bash -c "echo '$fixture' | jq -e '(.files_to_inspect // []) | length == 0'"
  assert_success
}

@test "ac4: specialist output with empty files_to_inspect array parses successfully" {
  # AC: files_to_inspect が明示的に空配列で渡された場合もパース可能
  local fixture
  fixture=$(cat <<'EOF'
{
  "status": "PASS",
  "files_to_inspect": [],
  "findings": []
}
EOF
)

  run bash -c "echo '$fixture' | jq -e '.files_to_inspect == []'"
  assert_success
}
