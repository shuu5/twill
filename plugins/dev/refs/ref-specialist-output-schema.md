# ref-specialist-output-schema

全 specialist が準拠する共通出力スキーマ。ADR-004 の実装仕様。

merge-gate / phase-review が機械的に消費可能な構造化出力を定義する。

## JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["status", "findings"],
  "properties": {
    "status": {
      "type": "string",
      "enum": ["PASS", "WARN", "FAIL"],
      "description": "PASS: CRITICAL/WARNING なし, WARN: WARNING はあるが CRITICAL なし, FAIL: CRITICAL が1件以上"
    },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["severity", "confidence", "file", "line", "message", "category"],
        "properties": {
          "severity": {
            "type": "string",
            "enum": ["CRITICAL", "WARNING", "INFO"]
          },
          "confidence": {
            "type": "integer",
            "minimum": 0,
            "maximum": 100,
            "description": "確信度。merge-gate は confidence >= 80 でフィルタ"
          },
          "file": {
            "type": "string",
            "description": "対象ファイルの相対パス"
          },
          "line": {
            "type": "integer",
            "minimum": 1,
            "description": "対象行番号"
          },
          "message": {
            "type": "string",
            "description": "finding の説明"
          },
          "category": {
            "type": "string",
            "enum": ["vulnerability", "bug", "coding-convention", "structure", "principles"],
            "description": "finding の分類"
          }
        }
      }
    }
  }
}
```

## status

| 値 | 条件 | 意味 |
|----|------|------|
| `PASS` | findings に CRITICAL も WARNING もない | 問題なし |
| `WARN` | WARNING はあるが CRITICAL はない | 警告あり、続行可 |
| `FAIL` | CRITICAL が 1 件以上 | ブロッキング問題あり |

### 自動導出ルール

status は findings 配列の severity から機械的に導出する。AI の裁量で status を決定してはならない。

1. findings に `severity == "CRITICAL"` が 1 件以上 → `FAIL`
2. findings に `severity == "WARNING"` が 1 件以上 → `WARN`
3. それ以外 → `PASS`

## severity

3 段階のみ許可。

| 値 | 用途 |
|----|------|
| `CRITICAL` | ブロッキング問題（セキュリティ脆弱性、データ損失リスク等） |
| `WARNING` | 注意が必要だがブロックしない問題 |
| `INFO` | 改善提案・情報提供 |

### 旧表記からの変換マッピング

| 旧表記 | 新表記 | 根拠 |
|--------|--------|------|
| Critical | CRITICAL | そのまま |
| High | WARNING | 3 段階に統一 |
| Warning | WARNING | 統合 |
| Medium | INFO | 3 段階に統一 |
| Suggestion | INFO | 統合 |
| Info | INFO | そのまま |

## confidence

- 範囲: 0-100（整数）
- merge-gate フィルタ閾値: `confidence >= 80`
- specialist は各 finding に必ず confidence を付与する

## category

| 値 | 対象 specialist |
|----|----------------|
| `vulnerability` | worker-security-reviewer, worker-rls-reviewer |
| `bug` | worker-code-reviewer, worker-*-reviewer (conditional) |
| `coding-convention` | worker-code-reviewer |
| `structure` | worker-structure |
| `principles` | worker-principles |

## 消費側パースルール

### サマリー行パース

```regex
status: (PASS|WARN|FAIL)
```

specialist 出力の先頭から上記パターンを検索。最初のマッチを status とする。

### ブロック判定

```
IF findings に (severity == "CRITICAL" AND confidence >= 80) が 1 件以上
THEN → BLOCK（merge-gate REJECT）
ELSE → PASS
```

### パース失敗時フォールバック

specialist 出力が上記スキーマに準拠しない場合:
1. 出力全文を 1 つの WARNING finding として扱う
2. `confidence: 50` を設定（ブロック閾値以下）
3. 手動レビューを要求するメッセージを追加

## output_schema: custom 除外条件

deps.yaml の specialist/agent エントリに `output_schema: custom` を指定した場合:

- 共通スキーマの few-shot テンプレート注入をスキップする
- 消費側のパース失敗フォールバック（WARNING, confidence=50）は常に適用される
- merge-gate のブロック閾値（confidence >= 80）には達しないため、custom specialist が自動 REJECT を引き起こすことはない

### 使用例

```yaml
agents:
  worker-custom-analyzer:
    type: specialist
    path: agents/worker-custom-analyzer/AGENT.md
    output_schema: custom
    description: "独自形式で出力する specialist"
```

## Model 割り当て

### 判定基準

| Model | 判定基準 | 用途 |
|-------|---------|------|
| **haiku** | 構造チェック・パターンマッチ。LLM 判断が最小限で済む検証タスク | 型検証、テンプレート検証、環境変数チェック |
| **sonnet** | コードレビュー・品質判断・コード生成。LLM の判断力が必要なタスク | コード品質、セキュリティ、E2E生成 |
| **opus** | specialist には使用しない | Controller/Workflow のみ |

### haiku (4 件)

| Specialist | 根拠 |
|---|---|
| worker-structure | loom check/audit の結果をパターンマッチで検証 |
| worker-env-validator | .env.example との突合（パターンマッチ） |
| worker-data-validator | データファイルの形式チェック（パターンマッチ） |
| template-validator | Issue テンプレートの必須フィールド検証 |

### sonnet (23 件)

| Specialist | 根拠 |
|---|---|
| worker-code-reviewer | コード品質の判断が必要 |
| worker-security-reviewer | セキュリティ脆弱性の検出に判断力が必要 |
| worker-nextjs-reviewer | フレームワーク固有の品質判断 |
| worker-fastapi-reviewer | フレームワーク固有の品質判断 |
| worker-hono-reviewer | フレームワーク固有の品質判断 |
| worker-r-reviewer | 統計的正確性の判断 |
| worker-e2e-reviewer | テスト品質の判断 |
| worker-spec-reviewer | Scenario 品質の判断 |
| worker-llm-output-reviewer | LLM 出力品質の判断 |
| worker-llm-eval-runner | LLM 基準評価の判断 |
| worker-supabase-migration-checker | SQL 品質の判断 |
| worker-rls-reviewer | RLS ポリシーの論理検証 |
| worker-principles | 5 原則の適用判断 |
| worker-architecture | アーキテクチャパターンの適用判断 |
| context-checker | プロジェクトコンテキストの分析 |
| docs-researcher | ドキュメント取得・分析 |
| pr-test | テスト実行・結果分析 |
| e2e-quality | 偽陽性リスクの判断 |
| autofix-loop | 修正コード生成 |
| spec-scaffold-tests | テストコード生成 |
| e2e-generate | E2E テストコード生成 |
| e2e-heal | E2E テスト修復（コード生成） |
| e2e-visual-heal | Visual 検証修復（コード生成） |
