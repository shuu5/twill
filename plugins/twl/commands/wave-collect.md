---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 10
---
# Wave 結果収集

Wave 完了後に co-autopilot の実行結果を収集し、Wave サマリを生成する。

## 引数

| 引数 | 説明 | デフォルト |
|------|------|----------|
| `WAVE_NUM` | Wave 番号（plan.yaml の phase 番号） | 1 |

## 実行ロジック（MUST）

### Step 1: plan.yaml から Issue リスト取得

```bash
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
PLAN_FILE="${AUTOPILOT_DIR}/plan.yaml"
WAVE_NUM="${WAVE_NUM:-1}"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "[wave-collect] Error: plan.yaml が見つかりません: $PLAN_FILE"
  exit 1
fi

# Phase N の Issue リストを取得（shell 解析 — PyYAML が対応しない plan.yaml 形式に対応）
ISSUES=$(awk -v wave="$WAVE_NUM" '
  $0 == "  - phase: " wave { found=1; next }
  found && /^  - phase: / { exit }
  found && /^    - [0-9]/ { gsub(/[^0-9]/, ""); print }
' "$PLAN_FILE" | tr '\n' ' ' | sed 's/ *$//')

if [[ -z "$ISSUES" ]]; then
  echo "[wave-collect] Warning: Wave ${WAVE_NUM} に対応する Phase が見つかりません"
  exit 0
fi

echo "[wave-collect] Wave ${WAVE_NUM}: Issue リスト = ${ISSUES}"
```

### Step 2: 各 Issue の結果を収集

```bash
declare -a RESULTS
TOTAL=0
DONE_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0
TOTAL_RETRIES=0
INTERVENTION_COUNT=0
# skip 理由カウンタ（3 カテゴリ enum、ADR-014 機械判定）
SKIP_STATE_FILE_MISSING=0
SKIP_DEPENDENCY_FAILED=0
SKIP_STATUS_OTHER=0
SKIP_STATE_FILE_MISSING_ISSUES=""
SKIP_DEPENDENCY_FAILED_ISSUES=""
SKIP_STATUS_OTHER_ISSUES=""

for ISSUE in $ISSUES; do
  ISSUE_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE}.json"
  TOTAL=$((TOTAL + 1))

  if [[ ! -f "$ISSUE_FILE" ]]; then
    echo "[wave-collect] Warning: Issue #${ISSUE} の状態ファイルが見つかりません — スキップ"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    SKIP_STATE_FILE_MISSING=$((SKIP_STATE_FILE_MISSING + 1))
    SKIP_STATE_FILE_MISSING_ISSUES="${SKIP_STATE_FILE_MISSING_ISSUES:+${SKIP_STATE_FILE_MISSING_ISSUES} }#${ISSUE}"
    RESULTS+=("| #${ISSUE} | unknown | — | 0 |")
    continue
  fi

  STATUS=$(python3 -c "import json; d=json.load(open('${ISSUE_FILE}')); print(d.get('status','unknown'))")
  PR=$(python3 -c "import json; d=json.load(open('${ISSUE_FILE}')); print(d.get('pr') or '')")
  RETRY=$(python3 -c "import json; d=json.load(open('${ISSUE_FILE}')); print(d.get('retry_count', 0))")
  FAILURE=$(python3 -c "import json; d=json.load(open('${ISSUE_FILE}')); f=d.get('failure'); print(f if f else '')")

  case "$STATUS" in
    done)
      DONE_COUNT=$((DONE_COUNT + 1))
      ;;
    failed)
      FAILED_COUNT=$((FAILED_COUNT + 1))
      if [[ "$FAILURE" == "dependency_failed" ]]; then
        SKIP_DEPENDENCY_FAILED=$((SKIP_DEPENDENCY_FAILED + 1))
        SKIP_DEPENDENCY_FAILED_ISSUES="${SKIP_DEPENDENCY_FAILED_ISSUES:+${SKIP_DEPENDENCY_FAILED_ISSUES} }#${ISSUE}"
      fi
      ;;
    *)
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      if [[ "$FAILURE" == "dependency_failed" ]]; then
        SKIP_DEPENDENCY_FAILED=$((SKIP_DEPENDENCY_FAILED + 1))
        SKIP_DEPENDENCY_FAILED_ISSUES="${SKIP_DEPENDENCY_FAILED_ISSUES:+${SKIP_DEPENDENCY_FAILED_ISSUES} }#${ISSUE}"
      else
        SKIP_STATUS_OTHER=$((SKIP_STATUS_OTHER + 1))
        SKIP_STATUS_OTHER_ISSUES="${SKIP_STATUS_OTHER_ISSUES:+${SKIP_STATUS_OTHER_ISSUES} }#${ISSUE}"
      fi
      ;;
  esac

  if [[ "$RETRY" -gt 0 ]]; then
    INTERVENTION_COUNT=$((INTERVENTION_COUNT + 1))
    TOTAL_RETRIES=$((TOTAL_RETRIES + RETRY))
  fi

  PR_DISPLAY="${PR:-—}"
  FAILURE_NOTE=""
  if [[ -n "$FAILURE" && "$STATUS" == "failed" ]]; then
    FAILURE_NOTE=" (${FAILURE:0:50})"
  fi

  RESULTS+=("| #${ISSUE} | ${STATUS}${FAILURE_NOTE} | ${PR_DISPLAY} | ${RETRY} |")
done
```

### Step 3: 統計計算と出力

```bash
OUTPUT_DIR="${AUTOPILOT_DIR}/../.supervisor"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="${OUTPUT_DIR}/wave-${WAVE_NUM}-summary.md"

# 介入率計算
if [[ "$TOTAL" -gt 0 ]]; then
  INTERVENTION_RATE=$(python3 -c "print(f'{${INTERVENTION_COUNT}/${TOTAL}*100:.1f}%')")
  AVG_RETRIES=$(python3 -c "print(f'{${TOTAL_RETRIES}/${TOTAL}:.2f}')" 2>/dev/null || echo "0.00")
else
  INTERVENTION_RATE="0.0%"
  AVG_RETRIES="0.00"
fi

# 完遂率計算（分母から state_file_missing と dependency_failed を除外）
COMPLETION_RATE_DENOM=$((TOTAL - SKIP_STATE_FILE_MISSING - SKIP_DEPENDENCY_FAILED))
if [[ "$COMPLETION_RATE_DENOM" -gt 0 ]]; then
  COMPLETION_RATE=$(python3 -c "print(f'{${DONE_COUNT}/${COMPLETION_RATE_DENOM}*100:.1f}%')")
else
  COMPLETION_RATE="N/A"
fi

GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# skip 内訳テーブル行を生成
SKIP_TABLE_ROWS=""
SKIP_TABLE_ROWS+="| state_file_missing | ${SKIP_STATE_FILE_MISSING} | ${SKIP_STATE_FILE_MISSING_ISSUES:--} |"$'\n'
SKIP_TABLE_ROWS+="| dependency_failed | ${SKIP_DEPENDENCY_FAILED} | ${SKIP_DEPENDENCY_FAILED_ISSUES:--} |"$'\n'
SKIP_TABLE_ROWS+="| status_other | ${SKIP_STATUS_OTHER} | ${SKIP_STATUS_OTHER_ISSUES:--} |"

cat > "$OUTPUT_FILE" <<SUMMARY
# Wave ${WAVE_NUM} サマリ

生成日時: ${GENERATED_AT}

## 概要統計

| 項目 | 件数 |
|------|------|
| 対象 Issue 総数 | ${TOTAL} |
| 完了 (done) | ${DONE_COUNT} |
| 失敗 (failed) | ${FAILED_COUNT} |
| 未完了/スキップ | ${SKIPPED_COUNT} |
| 完遂率 | ${COMPLETION_RATE} |
| 介入あり Issue 数 | ${INTERVENTION_COUNT} |
| 介入率 | ${INTERVENTION_RATE} |
| 平均介入回数 | ${AVG_RETRIES} |

## Issue 一覧

| Issue | ステータス | PR | 介入回数 |
|-------|-----------|-----|---------|
$(printf '%s\n' "${RESULTS[@]}")

## 介入パターン統計

- 介入 Issue 総数: ${INTERVENTION_COUNT} / ${TOTAL}
- 介入率: ${INTERVENTION_RATE}
- 総介入回数: ${TOTAL_RETRIES}
- 平均介入回数: ${AVG_RETRIES}

## skip 内訳

| 理由 | 件数 | 該当 Issue |
|------|------|-----------|
${SKIP_TABLE_ROWS}
SUMMARY

echo "[wave-collect] Wave ${WAVE_NUM} サマリを生成しました: ${OUTPUT_FILE}"
echo "[wave-collect] 統計: total=${TOTAL}, done=${DONE_COUNT}, failed=${FAILED_COUNT}, skipped=${SKIPPED_COUNT}, 介入=${INTERVENTION_COUNT}/${TOTAL}"
```

### Step 4: specialist completeness 監査（SHOULD）

Wave 内の全 Issue を一括監査する。`SPECIALIST_AUDIT_MODE=warn`（bootstrapping 期間中）は常に exit 0 のため merge を阻害しない。結果を `.audit/wave-${WAVE_NUM}/specialist-audit.log` に追記し、FAIL 行があれば次 Wave の手動調査対象としてログに記録する。

```bash
# Wave 内の全 Issue について specialist completeness を監査
_audit_log=".audit/wave-${WAVE_NUM}/specialist-audit.log"
mkdir -p ".audit/wave-${WAVE_NUM}"
for issue_json in "${AUTOPILOT_DIR:-.autopilot}"/issues/issue-*.json; do
  [[ -f "$issue_json" ]] || continue
  _issue_num=$(basename "$issue_json" | sed 's/issue-\([0-9]*\)\.json/\1/')
  # --warn-only で merge を阻害しない。JSON 出力でログに記録（FAIL 検出可能）
  bash "${CLAUDE_PLUGIN_ROOT:-plugins/twl}/scripts/specialist-audit.sh" \
    --issue "$_issue_num" --warn-only \
    >> "$_audit_log" 2>&1 || true
done
# FAIL 行の検出（--warn-only で exit 0 だが JSON の "status":"FAIL" で識別）
if grep -q '"status":"FAIL"' "$_audit_log" 2>/dev/null; then
  echo "WARN: specialist-audit に FAIL あり — ${_audit_log} を確認してください" >&2
fi
echo "[wave-collect] specialist-audit 完了: ${_audit_log}"
```

## 禁止事項（MUST NOT）

- Issue の状態を変更してはならない（読み取りのみ）
- 個別 Issue のデータ取得失敗でワークフロー全体を停止してはならない
- `.supervisor/` ディレクトリが存在しない場合は自動作成する（停止禁止）
