#!/bin/bash
# classify-failure.sh
# PR cycle停止時の障害原因を harness / code / unknown に分類
# Usage: classify-failure.sh <snapshot-dir>

set -euo pipefail

SNAPSHOT_DIR="${1:?Usage: classify-failure.sh <snapshot-dir>}"

if [ ! -d "$SNAPSHOT_DIR" ]; then
    echo "エラー: スナップショットディレクトリが見つかりません: $SNAPSHOT_DIR" >&2
    exit 1
fi

# --- 分類結果変数 ---
CLASSIFICATION="unknown"
CONFIDENCE=0
EVIDENCE=()
COMPONENT=""

# --- エラーログ収集 ---
# スナップショット内の全テキストファイルを結合してエラーパターンを検索
shopt -s nullglob
ERROR_TEXT=""
for f in "$SNAPSHOT_DIR"/*.md "$SNAPSHOT_DIR"/*.json "$SNAPSHOT_DIR"/workers/*.md; do
    [ -f "$f" ] && ERROR_TEXT+=$(cat "$f")$'\n'
done
shopt -u nullglob

# --- ハーネスパターン検出 ---
harness_score=0
code_score=0

# Pattern 1: Skill/Command実行エラー
if echo "$ERROR_TEXT" | grep -qiE 'SKILL\.md|skill.*parse|command not found.*skill|skill.*not found|command.*not found.*(dev|twl):'; then
    harness_score=$((harness_score + 25))
    EVIDENCE+=("Skill/Command実行エラーを検出")
    # コンポーネント特定: SKILL.mdのパスを抽出
    skill_path=$(echo "$ERROR_TEXT" | grep -oP 'plugins/dev/\S*SKILL\.md' | head -1 || true)
    [ -n "$skill_path" ] && COMPONENT="$skill_path"
fi

# Pattern 2: specialist起動条件不備
if echo "$ERROR_TEXT" | grep -qiE 'specialist.*not.*spawn|expected.*specialist|worker.*not.*found|subagent.*fail|agent.*spawn.*error'; then
    harness_score=$((harness_score + 25))
    EVIDENCE+=("specialist起動条件不備を検出")
fi

# Pattern 3: サービス定義と実態の不整合
# 注: CWD=プロジェクトルートで実行される前提（controller-pr-cycle から呼び出し）
if echo "$ERROR_TEXT" | grep -qiE 'connection refused|ECONNREFUSED'; then
    # services.yaml or docker-compose.yml が存在するか確認
    if [ -f "services.yaml" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        harness_score=$((harness_score + 20))
        EVIDENCE+=("サービス接続拒否 + サービス定義ファイル存在")
        [ -z "$COMPONENT" ] && COMPONENT="services.yaml / docker-compose.yml"
    fi
fi

# Pattern 4: テンプレート設定不足
if echo "$ERROR_TEXT" | grep -qiE '\.env.*not found|\.env.*missing|environment variable.*not set|env.*undefined|template.*missing|TEMPLATE_'; then
    harness_score=$((harness_score + 20))
    EVIDENCE+=("テンプレート/環境変数設定不足を検出")
fi

# Pattern 5: Hook実行エラー
if echo "$ERROR_TEXT" | grep -qiE 'hook.*error|hook.*fail|settings\.json.*error|hooks\.json.*error|PreToolUse.*error|PostToolUse.*error'; then
    harness_score=$((harness_score + 25))
    EVIDENCE+=("Hook実行エラーを検出")
    [ -z "$COMPONENT" ] && COMPONENT="settings.json / hooks.json"
fi

# Pattern 6: autopilot自体のエラー
if echo "$ERROR_TEXT" | grep -qiE 'autopilot\.sh|cld-autopilot|autopilot.*error|autopilot.*fail'; then
    harness_score=$((harness_score + 25))
    EVIDENCE+=("autopilotエラーを検出")
    [ -z "$COMPONENT" ] && COMPONENT="scripts/cld-autopilot"
fi

# --- コードパターン検出 ---
# Pattern: TypeScript/lint/テストアサーション失敗
if echo "$ERROR_TEXT" | grep -qiE 'TypeError|ReferenceError|SyntaxError|lint.*error|eslint|tsc.*error'; then
    code_score=$((code_score + 30))
fi

if echo "$ERROR_TEXT" | grep -qiE 'AssertionError|expect\(.*\)\.to|assert.*fail|test.*fail.*FAIL'; then
    code_score=$((code_score + 30))
fi

# --- 分類判定 ---
# 等スコア時は harness を優先（ハーネス問題はユーザーコードでは修正不能なため早期報告を重視）
if [ $harness_score -gt 0 ] && [ $harness_score -ge $code_score ]; then
    CLASSIFICATION="harness"
    CONFIDENCE=$((50 + harness_score))
    [ $CONFIDENCE -gt 100 ] && CONFIDENCE=100
elif [ $code_score -gt 0 ] && [ $code_score -gt $harness_score ]; then
    CLASSIFICATION="code"
    CONFIDENCE=$((50 + code_score))
    [ $CONFIDENCE -gt 100 ] && CONFIDENCE=100
else
    CLASSIFICATION="unknown"
    CONFIDENCE=30
fi

# --- JSON出力 ---
# evidence配列をJSON形式に変換
EVIDENCE_JSON="[]"
if [ ${#EVIDENCE[@]} -gt 0 ]; then
    EVIDENCE_JSON=$(printf '%s\n' "${EVIDENCE[@]}" | jq -R . | jq -s .)
fi

OUTPUT_FILE="$SNAPSHOT_DIR/05.5-failure-classification.json"

jq -n \
    --arg classification "$CLASSIFICATION" \
    --argjson confidence "$CONFIDENCE" \
    --argjson evidence "$EVIDENCE_JSON" \
    --arg component "$COMPONENT" \
    '{
        classification: $classification,
        confidence: $confidence,
        evidence: $evidence,
        component: $component,
        issue_url: null
    }' > "$OUTPUT_FILE"

echo "分類完了: $CLASSIFICATION (confidence: $CONFIDENCE%)"
echo "出力: $OUTPUT_FILE"
