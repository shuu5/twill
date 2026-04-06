## Context

`deep_validate()` は (A) Controller 行数チェック, (B) Reference 配置監査, (C) Frontmatter-Body ツール整合性 の 3 チェックを持つ。specialist 固有のチェックはない。

`audit_report()` の Section 5 (Self-Contained) は specialist の prompt body 内の Purpose/Output/Constraint キーワードを検出する。出力スキーマの準拠状況は未検証。

Issue #33 は specialist の prompt body に出力スキーマキーワード（PASS/FAIL, findings, severity, confidence）が含まれるかを検証するチェックを追加する。

## Goals / Non-Goals

**Goals:**

- deep-validate に specialist 出力スキーマキーワード検証 (D) を追加
- `output_schema: custom` による検証スキップ
- audit Section 5 の Output 列にスキーマ準拠状況を反映

**Non-Goals:**

- JSON 構造の厳密パース（キーワードベースで十分）
- specialist 以外の型への適用
- types.yaml への output_schema フィールド追加（deps.yaml レベルのフィールド）

## Decisions

### 1. キーワード定義を定数として配置

```python
REQUIRED_OUTPUT_KEYWORDS = {
    "result_values": {"PASS", "FAIL"},     # いずれか1つ以上
    "structure": {"findings"},              # 必須
    "severity": {"severity"},              # 必須
    "confidence": {"confidence"},          # 必須
}
```

`_check_self_contained_keywords()` と同レベルにヘルパー関数 `_check_output_schema_keywords()` を追加。

### 2. deep-validate チェック (E) の追加

`deep_validate()` 内に新セクション `(E) Specialist 出力スキーマ検証` を追加。`output_schema: custom` のものはスキップ、`output_schema` が存在するが `custom` 以外の場合は WARNING。

### 3. audit Section 5 の列拡張

既存の `| Component | Type | Purpose | Output | Constraint | Severity |` に `Schema` 列を追加:
`| Component | Type | Purpose | Output | Constraint | Schema | Severity |`

Schema 列の値: `Yes` / `No` / `Skip`（custom の場合）

### 4. severity 判定への Schema 統合

Section 5 の severity 判定: 既存の `purpose and output` に加えて `schema` も OK 判定に影響させる。schema 不足のみの場合は WARNING（CRITICAL にはしない）。

## Risks / Trade-offs

- **偽陽性**: キーワードベース検出のため、自然言語文脈で出現するケースも検出する。Issue で「許容する」と明記されており、仕様通り。
- **deps.yaml 互換性**: `output_schema` は既存フィールドにない新規フィールド。未設定時は検証を実行する（デフォルトで検証有効）。
