# ref-specialist-output-schema

全 specialist が準拠する共通出力スキーマ。ADR-004 の実装仕様。

## JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["status", "findings"],
  "properties": {
    "status": {
      "type": "string",
      "enum": ["PASS", "WARN", "FAIL"]
    },
    "files_to_inspect": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Pilot が深堀すべき相対パスのリスト（5-10 件目安）。探索系 specialist のみ使用。省略時は空配列扱い。"
    },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["severity", "confidence", "file", "line", "message", "category"],
        "properties": {
          "severity": { "type": "string", "enum": ["CRITICAL", "WARNING", "INFO"] },
          "confidence": { "type": "integer", "minimum": 0, "maximum": 100 },
          "file": { "type": "string" },
          "line": { "type": "integer", "minimum": 1 },
          "message": { "type": "string" },
          "category": {
            "type": "string",
            "enum": ["vulnerability", "bug", "coding-convention", "structure", "principles", "ac-alignment", "ac-alignment-unknown", "architecture-drift", "chain-integrity-drift", "experiment-integrity", "spec-vocabulary", "spec-structure", "spec-ssot", "spec-temporal"]
          },
          "finding_target": { "type": "string", "enum": ["issue_description", "codebase_state"] }
        }
      }
    }
  }
}
```

## status 導出ルール

findings の severity から機械的に導出（AI 裁量禁止）:
- CRITICAL が 1 件以上 → `FAIL`
- WARNING が 1 件以上（CRITICAL なし）→ `WARN`
- それ以外 → `PASS`

## severity

| 値 | 用途 |
|----|------|
| `CRITICAL` | ブロッキング問題（セキュリティ脆弱性、データ損失リスク等） |
| `WARNING` | 注意が必要だがブロックしない |
| `INFO` | 改善提案・情報提供 |

旧表記変換: Critical→CRITICAL, High/Warning→WARNING, Medium/Suggestion/Info→INFO

## confidence

0-100 整数。merge-gate フィルタ閾値: `confidence >= 80`。

**書き込み側 invariant**: CRITICAL severity の Finding は confidence >= 80 で書き込むこと。
checkpoint.py の `critical_count` は confidence フィルタを持たないため、各 ac-verify 書き込み経路がこの invariant を保証する責務を持つ（ac-impl-coverage-check.sh: confidence=90、LLM delegate パス: confidence=80）。

## category

**merge-gate specialist 用:**

| 値 | 対象 |
|----|------|
| `vulnerability` | security-reviewer, rls-reviewer |
| `bug` | code-reviewer, *-reviewer (conditional) |
| `coding-convention` | code-reviewer |
| `structure` | worker-structure |
| `principles` | worker-principles |
| `ac-alignment` | issue-pr-alignment（意味的整合性） |
| `ac-alignment-unknown` | issue-pr-alignment（判断不能 AC、INFO のみ） |
| `architecture-drift` | worker-architecture |
| `chain-integrity-drift` | worker-workflow-integrity |
| `experiment-integrity` | specialist-exp-reviewer (EXP 4-state lattice + verify_source whitelist + smoke pass=true 意味的妥当性 + bats quality との clash 検出) |
| `spec-vocabulary` | specialist-spec-review-vocabulary (Phase F 軸 1: vocabulary table forbidden synonym + glossary §11 deprecated entries + canonical name 違反) |
| `spec-structure` | specialist-spec-review-structure (Phase F 軸 2: cross-ref + id anchor + table column + changelog timeline + R-1/R-2 適用確認) |
| `spec-ssot` | specialist-spec-review-ssot (Phase F 軸 3: ADR + 不変条件 + EXP status + registry-schema 整合) |
| `spec-temporal` | specialist-spec-review-temporal (Phase F 軸 4: R-14 時系列 narration + R-15 デモコード + R-16 archive 移動 + R-17 changes/ lifecycle + R-18 ReSpec markup) |

**co-issue specialist 用**（merge-gate specialist は使用禁止）:

| 値 | 対象 |
|----|------|
| `ambiguity` | issue-critic |
| `assumption` | issue-critic |
| `scope` | issue-critic |
| `feasibility` | issue-feasibility |

## finding_target

Schema 上は optional だが co-issue specialist（issue-critic, issue-feasibility）は MUST。

| finding_target | ケース例 |
|---|---|
| `issue_description` | スコープ誤記、AC 曖昧、実装不可能な推奨 |
| `codebase_state` | バグ実在確認、変更影響範囲（省略時デフォルト） |

## ac-alignment specialist 追加要件（MUST）

1. **逐語引用必須**: `message` に Issue body / PR diff の逐語引用を含める。引用なし → parser が CRITICAL→WARNING に自動降格
2. **confidence 上限**: 原則 75。CRITICAL の場合のみ 80 許可
3. **ac-verify 重複回避**: ac-verify checkpoint を read し、既 CRITICAL 判定 AC は重複検出スキップ
4. **`alignment-override` ラベル**: 付与 PR では parser がこれらの Finding を全スキップ

## 消費側パースルール

**サマリー行**: `status: (PASS|WARN|FAIL)` を先頭から検索、最初のマッチを採用。

**ブロック判定**: `severity == "CRITICAL" AND confidence >= 80` が 1 件以上 → BLOCK（merge-gate REJECT）、それ以外 → PASS

**パース失敗時**: 出力全文を WARNING finding（confidence=50）として扱い、手動レビュー要求。

## output_schema: custom

deps.yaml で `output_schema: custom` 指定時、共通スキーマ注入をスキップ。パース失敗フォールバック（WARNING, confidence=50）は常に適用されるため、custom specialist が自動 REJECT を引き起こすことはない。

## Model 割り当て

| Model | 判定基準 | specialist 例 |
|-------|---------|--------------|
| **haiku** | 構造チェック・パターンマッチ | worker-structure, worker-env-validator, worker-data-validator, template-validator |
| **sonnet** | コードレビュー・品質判断・コード生成 | worker-code-reviewer, worker-security-reviewer, 各 *-reviewer, autofix-loop, e2e-generate, specialist-spec-explorer, specialist-spec-architect 等 |
| **opus** | deep audit (cross-AI bias 低減 / 深部 drift 検出 / semantic correctness) | specialist-exp-reviewer, specialist-spec-review-vocabulary, specialist-spec-review-structure, specialist-spec-review-ssot, specialist-spec-review-temporal |
