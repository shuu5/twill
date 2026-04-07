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
            "enum": ["vulnerability", "bug", "coding-convention", "structure", "principles", "ac-alignment", "ac-alignment-unknown"],
            "description": "finding の分類（merge-gate 共通）。co-issue specialist は co-issue 拡張 category を使用すること"
          },
          "finding_target": {
            "type": "string",
            "enum": ["issue_description", "codebase_state"],
            "description": "finding の対象。issue_description: Issue 記述の品質問題（曖昧性、スコープ誤記、実装不可能な提案）。codebase_state: コードベース状態の確認（バグ実在、脆弱性確認、変更影響範囲）。省略時は codebase_state として扱う（後方互換）"
          }
        }
      }
    }
  }
}
```

## co-issue specialist 追加要件

`finding_target` は JSON Schema 上は optional だが、co-issue specialist（issue-critic, issue-feasibility）は各 finding に必ず含めなければならない（MUST）。各 agent の frontmatter に required フィールドとして定義されている。

### finding_target 分類ガイドライン

| ケース | finding_target | 理由 |
|--------|---------------|------|
| スコープ記載ファイルが存在しない | `issue_description` | Issue のスコープ誤記 |
| AC が曖昧・定量化されていない | `issue_description` | Issue 記述の品質問題 |
| 推奨対応が実装不可能 | `issue_description` | Issue 設計の問題 |
| バグの実在を確認（コードに脆弱性あり） | `codebase_state` | コード問題の確認 |
| 変更影響範囲の指摘 | `codebase_state` | コードベースの情報提供 |

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

merge-gate specialist が使用する共通 category。

| 値 | 対象 specialist |
|----|----------------|
| `vulnerability` | worker-security-reviewer, worker-rls-reviewer |
| `bug` | worker-code-reviewer, worker-*-reviewer (conditional) |
| `coding-convention` | worker-code-reviewer |
| `structure` | worker-structure |
| `principles` | worker-principles |
| `ac-alignment` | worker-issue-pr-alignment（Issue body と PR diff の意味的整合性 finding） |
| `ac-alignment-unknown` | worker-issue-pr-alignment（達成度判断不能の AC、INFO のみ） |

### ac-alignment specialist の追加要件（MUST）

`category: ac-alignment` または `ac-alignment-unknown` を出力する specialist は以下を遵守すること:

1. **逐語引用必須**: 各 Finding の `message` フィールドに Issue body / PR diff の逐語引用を含める。引用なしの Finding は parser が CRITICAL → WARNING に自動降格する
2. **confidence 上限**: 原則 75（soft gate 役割を維持）。CRITICAL の場合のみ 80 を許可（明確なゼロ言及かつ ac-verify 未検出のケース）
3. **Issue 1 (ac-verify) との重複回避**: ac-verify checkpoint を read し、既に CRITICAL 判定済みの AC については重複検出をスキップする
4. **PR ラベル `alignment-override`**: 付与されている PR では parser がこれらの Finding をすべてスキップする

## category（co-issue 拡張）

co-issue specialist（issue-critic, issue-feasibility）が使用する category。merge-gate specialist はこれらの category を使用してはならない（MUST NOT）。

| 値 | 対象 specialist |
|----|----------------|
| `ambiguity` | issue-critic |
| `assumption` | issue-critic |
| `scope` | issue-critic |
| `feasibility` | issue-feasibility |

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
| worker-structure | twl check/audit の結果をパターンマッチで検証 |
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
