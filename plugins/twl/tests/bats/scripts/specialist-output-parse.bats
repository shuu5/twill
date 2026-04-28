#!/usr/bin/env bats
# specialist-output-parse.bats - unit tests for scripts/specialist-output-parse.sh

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: utility scripts unit test
# ---------------------------------------------------------------------------

@test "specialist-output-parse extracts status and findings from valid output" {
  local input='status: PASS
Some review text
```json
[{"severity":"WARNING","file":"test.ts","line":10,"message":"unused var","confidence":80}]
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "PASS"' > /dev/null
  echo "$output" | jq -e '.findings | length == 1' > /dev/null
  echo "$output" | jq -e '.parse_error == false' > /dev/null
}

@test "specialist-output-parse handles FAIL status" {
  local input='status: FAIL
```json
[{"severity":"CRITICAL","file":"auth.ts","line":5,"message":"SQL injection","confidence":95}]
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "FAIL"' > /dev/null
}

@test "specialist-output-parse handles WARN status" {
  local input='status: WARN
```json
[]
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "specialist-output-parse falls back on missing status" {
  run bash -c "echo 'no status here' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
  echo "$output" | jq -e '.parse_error == true' > /dev/null
  echo "$output" | jq -e '.findings[0].category == "parse-failure"' > /dev/null
}

@test "specialist-output-parse falls back on invalid JSON" {
  local input='status: PASS
```json
{invalid json}
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.parse_error == true' > /dev/null
}

@test "specialist-output-parse handles empty input" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.parse_error == true' > /dev/null
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
}

@test "specialist-output-parse handles status with no findings block" {
  run bash -c "echo 'status: PASS' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "PASS"' > /dev/null
  echo "$output" | jq -e '.findings == []' > /dev/null
  echo "$output" | jq -e '.parse_error == false' > /dev/null
}

@test "specialist-output-parse always produces valid JSON" {
  run bash -c "echo 'random garbage \$%^&*' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq '.' > /dev/null
}

@test "specialist-output-parse fallback finding has confidence 50" {
  run bash -c "echo 'no status here' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.findings[0].confidence == 50' > /dev/null
}

# ---------------------------------------------------------------------------
# AC1: 探索系 agent に files_to_inspect フィールドが記述されているか (RED)
# ---------------------------------------------------------------------------

@test "ac1: worker-architecture.md contains files_to_inspect in output section" {
  # AC: worker-architecture.md の出力形式節に files_to_inspect が記述されている
  # RED: 実装前は fail する
  run grep -q 'files_to_inspect' "$REPO_ROOT/agents/worker-architecture.md"
  assert_success
}

@test "ac1: worker-workflow-integrity.md contains files_to_inspect in output section" {
  # AC: worker-workflow-integrity.md の出力形式節に files_to_inspect が記述されている
  # RED: 実装前は fail する
  run grep -q 'files_to_inspect' "$REPO_ROOT/agents/worker-workflow-integrity.md"
  assert_success
}

@test "ac1: context-checker.md contains files_to_inspect in output section" {
  # AC: context-checker.md の出力形式節に files_to_inspect が記述されている
  # RED: 実装前は fail する
  run grep -q 'files_to_inspect' "$REPO_ROOT/agents/context-checker.md"
  assert_success
}

# ---------------------------------------------------------------------------
# AC2: 出力形式例が files_to_inspect を含む JSON 形式で記述されているか (RED)
# ---------------------------------------------------------------------------

@test "ac2: worker-architecture.md output example includes files_to_inspect key" {
  # AC: 出力形式は {"status": "PASS|WARN|FAIL", "files_to_inspect": [...], "findings": [...]}
  # RED: 実装前は fail する（現状の出力例には files_to_inspect がない）
  run grep -q '"files_to_inspect"' "$REPO_ROOT/agents/worker-architecture.md"
  assert_success
}

@test "ac2: worker-workflow-integrity.md output example includes files_to_inspect key" {
  # AC: 出力形式は {"status": "PASS|WARN|FAIL", "files_to_inspect": [...], "findings": [...]}
  # RED: 実装前は fail する（現状の出力例には files_to_inspect がない）
  run grep -q '"files_to_inspect"' "$REPO_ROOT/agents/worker-workflow-integrity.md"
  assert_success
}

@test "ac2: context-checker.md output example includes files_to_inspect key" {
  # AC: 出力形式は {"status": "PASS|WARN|FAIL", "files_to_inspect": [...], "findings": [...]}
  # RED: 実装前は fail する（現状の出力例には files_to_inspect がない）
  run grep -q '"files_to_inspect"' "$REPO_ROOT/agents/context-checker.md"
  assert_success
}

# ---------------------------------------------------------------------------
# AC3: Schema SSOT 2 箇所に files_to_inspect が optional として記載されているか (RED)
# ---------------------------------------------------------------------------

@test "ac3: ref-specialist-output-schema.md contains files_to_inspect field" {
  # AC: refs/ref-specialist-output-schema.md に files_to_inspect が optional field として追加される
  # RED: 実装前は fail する
  run grep -q 'files_to_inspect' "$REPO_ROOT/refs/ref-specialist-output-schema.md"
  assert_success
}

@test "ac3: architecture/contracts/specialist-output-schema.md contains files_to_inspect field" {
  # AC: architecture/contracts/specialist-output-schema.md に files_to_inspect が optional field として追加される
  # RED: 実装前は fail する
  run grep -q 'files_to_inspect' "$REPO_ROOT/architecture/contracts/specialist-output-schema.md"
  assert_success
}

@test "ac3: ref-specialist-output-schema.md does not list files_to_inspect in required array" {
  # AC: files_to_inspect は required には含めない（optional）
  # RED: 実装後に "required" ブロック内に files_to_inspect が存在しないことを確認
  # 実装前は files_to_inspect 自体が存在しないため grep -q が fail -> assert_failure で RED
  # 実装後は files_to_inspect が追加されるが required に含まれていないことを検証
  run bash -c "
    file='$REPO_ROOT/refs/ref-specialist-output-schema.md'
    # files_to_inspect が存在することを確認
    grep -q 'files_to_inspect' \"\$file\" || exit 1
    # required 配列に files_to_inspect が含まれていないことを確認
    # required は [\"status\", \"findings\"] のみであること
    python3 -c \"
import re, sys
content = open('\$file').read()
# JSON ブロックを抽出
m = re.search(r'\\\`\\\`\\\`json(.*?)\\\`\\\`\\\`', content, re.DOTALL)
if not m:
    sys.exit(1)
import json
schema = json.loads(m.group(1))
required = schema.get('required', [])
if 'files_to_inspect' in required:
    sys.exit(1)
sys.exit(0)
\"
  "
  assert_success
}
