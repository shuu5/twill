---
name: dev:self-improve-format
description: |
  self-improve Issue 共通フォーマット定義。
  全ソース（pr-cycle-analysis, merge-gate, retrospective, session-audit）で統一して使用。
type: reference
disable-model-invocation: true
---

# self-improve Issue 共通フォーマット

dev pluginの自己改善Issueの共通フォーマット定義。
全ソース（pr-cycle-analysis, merge-gate, retrospective, session-audit）で統一して使用する。

## ラベル

```bash
# ラベルが存在しない場合に作成（既存の場合はエラー無視）
gh label create "self-improve" --color "7057ff" --description "Dev plugin self-improvement opportunity" 2>/dev/null || true
```

## Issueタイトル規則

```
[Self-Improve] <カテゴリ>: <パターン名>
```

例: `[Self-Improve] prompt-quality: security-reviewer missing XSS detection`

## カテゴリ体系

| カテゴリ | 説明 | 検出ソース |
|---------|------|-----------|
| `prompt-quality` | specialistが検出すべき問題を見逃した | pr-cycle-analysis, merge-gate, retrospective |
| `rule-gap` | refs/baseline/に対応ルールがないパターンが繰り返し指摘される | pr-cycle-analysis, merge-gate, retrospective |
| `false-positive` | specialistが報告したが実際には問題でなかった指摘 | pr-cycle-analysis, merge-gate |
| `autofix-repeat` | autofix-loopで繰り返し適用された修正パターン | pr-cycle-analysis |
| `process-inefficiency` | ワークフローの非効率パターン | retrospective |
| `script-fragility` | Bash ERROR → AIが別コマンドで回避 → 成功するパターン | session-audit |
| `silent-failure` | Bash成功だが出力が期待と違い、AIが補償行動をとるパターン | session-audit |
| `ai-compensation` | Skill実行中にスキル定義外の推論・ツール使用が発生 | session-audit |
| `retry-loop` | 同一ツール+類似入力が3回以上連続するパターン | session-audit |
| `twl-inline-logic` | Skill実行中に長いBashパイプラインが出現するパターン | session-audit |

## Issue本文テンプレート

```markdown
## パターン
- **カテゴリ**: <prompt-quality|rule-gap|false-positive|autofix-repeat|process-inefficiency|script-fragility|silent-failure|ai-compensation|retry-loop|twl-inline-logic>
- **重複排除キー**: `<category>:<pattern-hash>`
- **検出ソース**: <pr-cycle-analysis|merge-gate|retrospective|session-audit>
- **信頼度**: <0-100>

## 検出根拠
<具体的な事例・エビデンス。PRリンク、specialist名、findingの内容等>

## 改善提案
<推奨される改善アクション。対象ファイル、変更内容のドラフト等>

## メタデータ
- 検出日: <YYYY-MM-DD>
- 検出PR: #<N>
- 発生頻度: <N回>
- 対象specialist: <specialist名 or N/A>
```

## 必須フィールド

| フィールド | 必須 | 説明 |
|-----------|------|------|
| カテゴリ | MUST | カテゴリ体系のいずれか |
| 重複排除キー | MUST | `<category>:<SHA256先頭8文字>` |
| 検出ソース | MUST | 検出元の識別 |
| 信頼度 | MUST | 0-100のスコア |
| 検出根拠 | MUST | 1つ以上の具体的エビデンス |
| 改善提案 | MUST | アクション可能な提案 |
| 検出日 | MUST | ISO形式の日付 |
| 検出PR | SHALL | 紐付くPR番号（retrospective時はN/A可） |
| 発生頻度 | SHALL | 検出回数 |
| 対象specialist | SHALL | 関連するspecialist名 |

## 重複排除キー生成ルール

```bash
# pattern-hashの生成: カテゴリ+パターン内容のSHA256先頭8文字
PATTERN_CONTENT="<カテゴリ>:<パターンの正規化された説明>"
PATTERN_HASH=$(echo -n "$PATTERN_CONTENT" | sha256sum | cut -c1-8)
DEDUP_KEY="<category>:${PATTERN_HASH}"
```

パターンの正規化:
- 小文字化
- 連続空白を単一スペースに
- specialist名 + 見逃し/誤検出パターンの組み合わせ

## 重複チェックフロー

```
1. doobidoo検索（高速）: mcp__doobidoo__memory_search で dedup_key を exact 検索
2. ヒット → 重複、起票スキップ
3. ミス → GitHub Issues検索: gh issue list --label "self-improve" --search "<dedup_key>"
4. ヒット → 重複、起票スキップ + doobidooにキャッシュ
5. ミス → 新規パターン、起票実行
```

## 起票条件

| 条件 | 閾値 | 動作 |
|------|------|------|
| 信頼度 >= 70 | confidence >= 70 | Issue起票対象 |
| 信頼度 < 70 | confidence < 70 | doobidooキャッシュのみ |
| --auto時 | confidence >= 70 | 人間承認スキップで自動起票 |
| 通常時 | confidence >= 70 | 人間承認を得てから起票 |
