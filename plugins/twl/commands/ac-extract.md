# AC（受け入れ基準）抽出

ブランチ名から Issue 番号を抽出し、Issue body から受け入れ基準を取得する。

## 入力

- `${SNAPSHOT_DIR}`: セッションスナップショットディレクトリ

## 出力

- `${SNAPSHOT_DIR}/01.5-ac-checklist.md`

## 冪等性

`${SNAPSHOT_DIR}/01.5-ac-checklist.md` が存在し内容がある場合、スキップ。

## 実行ロジック（MUST）

ブランチ名から Issue 番号を抽出する。

| 条件 | 動作 |
|------|------|
| Issue 番号あり | `parse-issue-ac.sh` を実行し AC を抽出 |
| Issue 番号なし | 「Issue 番号なし — スキップ」と記録 |
| AC セクションなし | 「AC セクションなし — スキップ」と記録 |
| AC 抽出成功 | 番号付き AC リストを保存 |

```bash
if [ -n "${ISSUE_NUM}" ]; then
    AC_OUTPUT=$(bash claude/plugins/twl/scripts/parse-issue-ac.sh "${ISSUE_NUM}" 2>/dev/null) && {
        printf '%s\n\n%s\n' "## 受け入れ基準（Issue #${ISSUE_NUM}）" "${AC_OUTPUT}" > "${SNAPSHOT_DIR}/01.5-ac-checklist.md"
    } || {
        echo "AC セクションなし — スキップ" > "${SNAPSHOT_DIR}/01.5-ac-checklist.md"
    }
fi
```

## チェックポイント（MUST）

チェーン完了。

