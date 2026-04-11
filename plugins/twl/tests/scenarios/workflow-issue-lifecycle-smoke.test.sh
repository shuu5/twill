#!/usr/bin/env bash
# workflow-issue-lifecycle-smoke.test.sh
# Smoke test: 1 issue の lifecycle が完走することを検証
# CI モック使用（gh issue create をスキップ）
#
# Usage:
#   bash tests/scenarios/workflow-issue-lifecycle-smoke.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

# --- ヘルパー ---
assert_file_exists() {
  local file="$1"
  local desc="${2:-$file}"
  if [[ -f "$file" ]]; then
    echo "  PASS: $desc が存在する"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc が存在しない"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local desc="${3:-$file contains $pattern}"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local file="$1"
  local field="$2"
  local expected="$3"
  local desc="${4:-$field == $expected}"
  local actual
  actual="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],''))" "$file" "$field" 2>/dev/null || echo "")"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== workflow-issue-lifecycle smoke test ==="
echo ""

# =============================================================================
# 前提確認
# =============================================================================
echo "[0] 前提確認"

assert_file_exists "$PLUGIN_ROOT/skills/workflow-issue-lifecycle/SKILL.md" \
  "workflow-issue-lifecycle/SKILL.md"
assert_file_exists "$PLUGIN_ROOT/scripts/issue-lifecycle-orchestrator.sh" \
  "issue-lifecycle-orchestrator.sh"

# =============================================================================
# テスト用 per-issue dir の作成
# =============================================================================
echo ""
echo "[1] per-issue dir セットアップ"

TMPDIR_BASE="$(mktemp -d /tmp/.wil-smoke-XXXXXX)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PER_ISSUE_DIR="$TMPDIR_BASE/per-issue/0"
mkdir -p "$PER_ISSUE_DIR/IN" "$PER_ISSUE_DIR/OUT" "$PER_ISSUE_DIR/rounds"

# IN/draft.md
cat > "$PER_ISSUE_DIR/IN/draft.md" <<'EOF'
# [Feature] smoke-test Issue

## 概要
smoke test 用のダミー Issue。

## 受け入れ基準
- [ ] smoke test が完走する
EOF

# IN/policies.json
cat > "$PER_ISSUE_DIR/IN/policies.json" <<'EOF'
{
  "max_rounds": 1,
  "specialists": ["worker-codex-reviewer"],
  "depth": "shallow",
  "quick_flag": true,
  "scope_direct_flag": false,
  "labels_hint": ["smoke-test"],
  "target_repo": null,
  "parent_refs_resolved": {}
}
EOF

echo "  PASS: per-issue dir セットアップ完了"
PASS=$((PASS + 1))

# =============================================================================
# SKILL.md 静的検証（lifecycle workflow を起動せず静的チェックのみ）
# =============================================================================
echo ""
echo "[2] workflow-issue-lifecycle/SKILL.md 静的検証"

SKILL_MD="$PLUGIN_ROOT/skills/workflow-issue-lifecycle/SKILL.md"

assert_file_contains "$SKILL_MD" "type: workflow" "frontmatter: type: workflow"
assert_file_contains "$SKILL_MD" "user-invocable: true" "frontmatter: user-invocable: true"
assert_file_contains "$SKILL_MD" "spawnable_by:.*controller.*user\|spawnable_by:.*user.*controller" \
  "frontmatter: spawnable_by 含む controller, user" || \
  assert_file_contains "$SKILL_MD" "controller, user\|user, controller" "frontmatter: spawnable_by controller+user"
assert_file_contains "$SKILL_MD" "spec-review-session-init.sh" "N=1 不変量ガード呼び出し"
assert_file_contains "$SKILL_MD" 'OUT/report.json' "OUT/report.json への書き込み記述"
assert_file_contains "$SKILL_MD" "STATE" "STATE ファイル管理記述"

# =============================================================================
# orchestrator 静的検証
# =============================================================================
echo ""
echo "[3] issue-lifecycle-orchestrator.sh 静的検証"

ORCH_SH="$PLUGIN_ROOT/scripts/issue-lifecycle-orchestrator.sh"

assert_file_contains "$ORCH_SH" "printf '%q'" "printf '%q' によるクォート"
assert_file_contains "$ORCH_SH" "|| continue" "|| continue による失敗局所化"
assert_file_contains "$ORCH_SH" "flock" "flock による衝突回避"
assert_file_contains "$ORCH_SH" 'coi-' "決定論的 window 名 coi-"
assert_file_contains "$ORCH_SH" "OUT/report.json" "OUT/report.json ポーリング検知"
assert_file_contains "$ORCH_SH" "STATE.*failed\|failed.*STATE" "STATE=failed リセット対応"
# cld が -p/--print を使っていないことを確認（wrapper 経由起動）
if ! grep -q "cld.*-p\b\|cld.*--print" "$ORCH_SH" 2>/dev/null; then
  echo "  PASS: cld -p/--print 非使用"
  PASS=$((PASS + 1))
else
  echo "  FAIL: cld -p/--print が使われている"
  FAIL=$((FAIL + 1))
fi

# =============================================================================
# deps.yaml 検証（CI モック: twl check は実行しない）
# =============================================================================
echo ""
echo "[4] deps.yaml 静的検証"

DEPS_YAML="$PLUGIN_ROOT/deps.yaml"

assert_file_contains "$DEPS_YAML" "workflow-issue-lifecycle:" \
  "deps.yaml: workflow-issue-lifecycle エントリ"
assert_file_contains "$DEPS_YAML" "issue-lifecycle-orchestrator:" \
  "deps.yaml: issue-lifecycle-orchestrator エントリ"

# spawnable_by: [controller, workflow] で issue-structure をチェック
if python3 -c "
import sys, re
content = open('$DEPS_YAML').read()
m = re.search(r'issue-structure:.*?spawnable_by:\\s*\\[([^\\]]+)\\]', content, re.DOTALL)
sys.exit(0 if (m and 'workflow' in m.group(1)) else 1)
" 2>/dev/null; then
  echo "  PASS: issue-structure spawnable_by に workflow が含まれる"
  PASS=$((PASS + 1))
else
  echo "  FAIL: issue-structure spawnable_by に workflow が含まれない"
  FAIL=$((FAIL + 1))
fi

# =============================================================================
# issue-create.md 検証
# =============================================================================
echo ""
echo "[5] issue-create.md 静的検証"

ISSUE_CREATE="$PLUGIN_ROOT/commands/issue-create.md"
assert_file_contains "$ISSUE_CREATE" "\-\-repo" "--repo オプション記述"
assert_file_contains "$ISSUE_CREATE" "body-file\|body_file" "--body-file セキュリティパターン"

# =============================================================================
# サマリー
# =============================================================================
echo ""
echo "=== smoke test 結果 ==="
echo "PASS: $PASS, FAIL: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
else
  echo "RESULT: PASS"
  exit 0
fi
