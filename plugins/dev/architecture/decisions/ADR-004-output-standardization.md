# ADR-004: Specialist 出力形式の標準化

## Status
Accepted

## Context

旧 dev plugin の 27 specialist の調査で以下の問題が判明:
- 設計判断 #10 の共通出力スキーマ (PASS/FAIL + findings[]) を実装している specialist が 0 個
- severity が 6 パターン混在 (Critical/High/Medium/Warning/Suggestion/PASS/WARN/FAIL/Info)
- confidence 値を出力に含める形式指定があるのは 2 specialist のみ
- merge-gate の confidence フィルタ (`>= 80`) が機能しない（入力形式が不定）
- phase-review の結果統合が AI の自由形式変換に依存

これは「LLM は判断のために使う。機械的にできることは機械に任せる」の設計哲学に反する。
出力形式の統一は「機械にできること」であり、AI の裁量に委ねるべきではない。

## Decision

### 出力形式の統一

1. **status**: `PASS` / `WARN` / `FAIL` の 3 値
   - PASS: CRITICAL/WARNING の findings なし
   - WARN: WARNING はあるが CRITICAL なし
   - FAIL: CRITICAL が 1 件以上

2. **severity**: `CRITICAL` / `WARNING` / `INFO` の 3 段階
   - 旧 Critical → CRITICAL
   - 旧 High/Warning → WARNING
   - 旧 Medium/Suggestion/Info → INFO

3. **findings 必須フィールド**: severity, confidence (0-100), file, line, message, category

4. **プロンプト内 few-shot 例**: 1 例のみ（コンテキスト消費 vs 準拠率のトレードオフ）

### 消費側の標準化

5. **サマリー行パース**: 正規表現 `status: (PASS|WARN|FAIL)` で機械的取得
6. **ブロック判定**: `severity == CRITICAL && confidence >= 80` のみ
7. **パース失敗時フォールバック**: 出力全文を WARNING として手動レビュー要求

### ツール活用の標準化

8. **TaskCreate/TaskList**: Controller/Autopilot Phase の進捗管理に使用。Specialist 内部では不使用
9. **AskUserQuestion**: ユーザー確認ポイントは選択肢形式（`[A]/[B]/[C]`）を必須化

## Consequences

### Positive
- merge-gate の severity フィルタが機械的に動作（AI 推論不要）
- phase-review の結果統合が構造化データに基づく（自由形式変換の排除）
- specialist 間の出力品質が均一化（ユーザー体験の一貫性）
- autopilot Phase 進捗が CLI 上で可視化

### Negative
- specialist プロンプトに few-shot 例を追加するため、コンテキスト消費が微増（1例 ≈ 150 tokens）
- 既存の specialist 出力形式からの移行コスト（C-3 で一括対応）
- output_schema: custom の specialist は個別対応が必要

### Risks
- LLM が few-shot 例を無視する可能性（研究では 72-90% の準拠率）
- composite 側のパーサーがパース失敗する場合のフォールバック品質
