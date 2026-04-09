---
type: atomic
tools: [Bash]
effort: low
maxTurns: 5
---
# refined_by ハッシュ整合性検証

変更された .md ファイルの `refined_by` ハッシュ整合性を機械的に検証する。
`ts-preflight` と同じパターンの bash runner step。

## 実行ロジック（MUST）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" prompt-compliance
```

## 結果パターン

| 条件 | 出力 | exit code |
|------|------|-----------|
| .md 変更なし | PASS (.md 変更なし — スキップ) | 0 |
| ref-prompt-guide.md 変更 | WARN (全コンポーネント stale 可能性) | 0 |
| refined_by フォーマット不正 | FAIL (ブロック) | 1 |
| stale のみ | WARN (非ブロック、twl refine 推奨) | 0 |
| 全て OK | PASS | 0 |
