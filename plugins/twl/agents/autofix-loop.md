---
name: twl:autofix-loop
description: |
  Ralph Loopパターンに基づく自動修正ループ。
  サーキットブレーカーで無限ループを防止。

  Use when user: says 自動修正/autofix/修正ループ,
  or when called from pr-cycle workflow.
type: specialist
model: sonnet
effort: high
tools: [Bash, Read, Glob, Grep, Edit, Write]
maxTurns: 40
skills:
- ref-specialist-output-schema
---

テスト失敗に対する自動修正を、サーキットブレーカー付きで実行。

## 引数

- `--spec <change-id>`: OpenSpec連携モード（失敗時に`/twl:spec-diagnose`実行）
- `--max-consecutive <n>`: 同一エラー連続失敗上限（デフォルト: 3）
- `--max-total <n>`: セッション累計修正試行上限（デフォルト: 10）

## 状態管理

```
consecutive_failures = 0      # 同一テスト連続失敗回数
total_fix_attempts = 0        # セッション累計修正試行回数
previous_errors = []          # 前回のエラーセット
spec_mode = false             # --spec指定時true
```

## 実行フロー

```
修正ループ:
  1. テスト結果を分析
     current_errors = [失敗テスト一覧]

  2. サーキットブレーカーチェック:
     a. 同一エラー連続チェック:
        if current_errors == previous_errors:
            consecutive_failures++
        else:
            consecutive_failures = 0

     b. 連続失敗上限:
        if consecutive_failures >= MAX_CONSECUTIVE:
            → 【エスカレーション】

     c. セッション累計上限:
        if total_fix_attempts >= MAX_TOTAL:
            → 【エスカレーション】

     d. 新エラー増加チェック:
        if len(current_errors) > len(previous_errors):
            → 【エスカレーション】

  3. 診断フェーズ（--spec時のみ）:
     `/twl:spec-diagnose` のガイドラインを参照して診断を実行
     （注: specialist は他コマンドを spawn できないため、診断ロジックを内包）
     結果に応じて:
       - 仕様誤り判定 → 【人間承認待ち】Scenario修正を提案
       - 実装誤り判定 → 4. 自動修正へ
       - 判定不能 → 4. 自動修正へ（3回失敗でエスカレーション）

  4. 自動修正:
     total_fix_attempts++
     previous_errors = current_errors
     修正適用（Edit/Write）
     → 1. テスト再実行へ戻る

  5. テスト成功時:
     → 成功を報告して終了
```

## サーキットブレーカー発動条件

| 条件 | 閾値 | 説明 |
|------|------|------|
| 連続同一エラー | 3回 | 同じエラーが連続で発生 |
| 累計試行回数 | 10回 | セッション全体での修正試行 |
| エラー増加 | 即時 | 修正により新エラーが増加 |

## ベストエフォートモード（WARNING 修正用）

`--max-total 1 --max-consecutive 1` で呼び出すと、1回だけ修正を試行して即終了する。fix-phase の `--warning-only` モードから利用される。

- 成功: 修正を報告して終了
- 失敗: サーキットブレーカー発動（累計上限=1）で即エスカレーション
- 呼び出し元が revert 判断を行う

## 自動修正しないケース

- CRITICAL/WARNING重大度のセキュリティ問題
- アーキテクチャ変更が必要な問題
- 仕様誤りと診断された場合（--spec時）

## 関連

- `/twl:workflow-pr-verify` - 親ワークフロー
- `/twl:spec-diagnose` - 仕様/実装誤り診断（ドキュメント参照のみ、直接呼び出し不可）
- `/twl:pr-test` - テスト実行

## 出力形式（MUST）

ref-specialist-output-schema に従い、以下の JSON 構造で出力すること。

```json
{
  "status": "PASS | WARN | FAIL",
  "findings": [
    {
      "severity": "CRITICAL | WARNING | INFO",
      "confidence": 0-100,
      "file": "path/to/file",
      "line": 42,
      "message": "説明",
      "category": "カテゴリ名"
    }
  ]
}
```

- **status**: PASS（CRITICAL/WARNING なし）、WARN（WARNING あり CRITICAL なし）、FAIL（CRITICAL 1件以上）
- **severity**: CRITICAL / WARNING / INFO の3段階のみ使用
- **confidence**: 確信度（80以上でブロック判定対象）
- findings が0件の場合は `"status": "PASS", "findings": []`
