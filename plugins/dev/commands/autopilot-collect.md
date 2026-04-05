# 変更ファイル収集

Phase 完了後、done 状態の Issue の PR 差分から変更ファイルリストを取得し session.json に保存する。
autopilot-phase-postprocess から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$ISSUES` | Phase 内の全 Issue 番号リスト（スペース区切り） |
| `$SESSION_STATE_FILE` | session.json のパス |

## 実行ロジック（MUST）

### collect_changed_files（単一 Issue）

```bash
collect_changed_files() {
  local issue=$1

  local status=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$issue" --field status)
  if [ "$status" != "done" ]; then
    return
  fi

  local pr_number=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$issue" --field pr_number)
  if [ -z "$pr_number" ]; then
    echo "[collect] Warning: Issue #${issue} の PR 番号取得失敗 — スキップ"
    return
  fi

  local changed_files=$(gh pr diff "$pr_number" --name-only 2>/dev/null)
  if [ -z "$changed_files" ]; then
    echo "[collect] Warning: Issue #${issue} PR #${pr_number} の差分取得失敗 — スキップ"
    return
  fi

  # session.json に追記（state-write.sh 経由）
  local files_json=$(echo "$changed_files" | jq -R -s 'split("\n") | map(select(. != ""))')
  bash $SCRIPTS_ROOT/state-write.sh --type session \
    --set "completed_issues.${issue}.pr=${pr_number}" \
    --set "completed_issues.${issue}.files=${files_json}" \
    --role pilot

  echo "[collect] Issue #${issue}: $(echo "$changed_files" | wc -l) ファイルの変更を記録"
}
```

### Phase 完了後の一括収集

```bash
for ISSUE in $ISSUES; do
  collect_changed_files "$ISSUE"
done
```

## 禁止事項（MUST NOT）

- マーカーファイル (.done) を参照してはならない（state-read で status 判定）
- PR 差分取得失敗でワークフロー全体を停止してはならない
