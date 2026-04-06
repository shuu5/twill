# テスト失敗の原因診断

テスト失敗の原因を診断し、仕様誤り（Scenario 修正が必要）か実装誤り（コード修正が必要）かを判定する。
診断結果の報告のみ行い、修正は行わない。

## 引数

- `--change-id <change-id>`: OpenSpec 提案 ID（必須）

## 前提条件

- `deltaspec/changes/<change-id>/test-mapping.yaml` が存在すること
- テストが実行済みで結果が取得可能なこと

## 実行フロー

### Step 1: 入力収集

- test-mapping.yaml: Scenario ↔ テストのマッピング
- テスト結果ファイル（Jest/pytest/testthat）
- 失敗テスト一覧を抽出

### Step 2: Scenario マッピング

失敗テストを test-mapping.yaml 経由で Scenario に紐付ける。

### Step 3: エラー分析

| エラータイプ | 例 | 分類 |
|-------------|-----|------|
| AssertionError | `expect(x).toBe(y)` 失敗 | 期待値不一致 |
| TypeError/ReferenceError | `undefined is not a function` | コードバグ |
| Exception | `throw new Error(...)` | 例外発生 |
| Timeout | `Exceeded timeout of 5000ms` | タイムアウト |

### Step 4: 判定ロジック

- **仕様誤り（spec_error）**: 同一 Scenario 複数失敗、期待値が一貫して異なる
- **実装誤り（impl_error）**: TypeError/ReferenceError/SyntaxError
- **LLM 品質問題（llm_quality_issue）**: コードテスト全 PASS だが llm-eval FAIL
- **判定不能（unknown）**: 信頼度 50 未満

### Step 5: JSON 出力

```json
{
  "change_id": "<change-id>",
  "diagnosis": "spec_error|impl_error|llm_quality_issue|unknown",
  "confidence": 85,
  "summary": "診断サマリー",
  "failed_scenarios": [...],
  "recommended_action": "推奨アクション",
  "next_steps": [...]
}
```

## PR-cycle 連携

fix-phase から条件付き呼び出し時:
- `spec_error` → 自動修正中止、人間確認待ち
- `impl_error` → 自動修正続行
- `llm_quality_issue` → 自動修正対象外、人間確認待ち
- `unknown` → 自動修正試行（3 回まで）

## 禁止事項（MUST NOT）

- 修正を行ってはならない（診断結果の報告のみ）
