# Contract: Specialist 共通出力スキーマ

ADR-004 の実装仕様。全 specialist が準拠する出力形式を定義する。

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
            "enum": ["vulnerability", "bug", "coding-convention", "structure", "principles", "architecture-violation", "architecture-drift", "chain-integrity-drift", "ambiguity", "assumption", "scope", "feasibility", "ac-alignment", "ac-alignment-unknown"],
            "description": "finding の分類"
          },
          "finding_target": {
            "type": "string",
            "enum": ["issue_description", "codebase_state"],
            "description": "co-issue specialist は MUST。省略時デフォルト: codebase_state"
          }
        }
      }
    }
  }
}
```

## フィールド説明

### status

| 値 | 条件 | 意味 |
|----|------|------|
| `PASS` | findings に CRITICAL も WARNING もない | 問題なし |
| `WARN` | WARNING はあるが CRITICAL はない | 警告あり、続行可 |
| `FAIL` | CRITICAL が 1 件以上 | ブロッキング問題あり |

status の自動導出ルール:
1. findings 配列をスキャン
2. `severity == "CRITICAL"` が 1 件以上 → `FAIL`
3. `severity == "WARNING"` が 1 件以上 → `WARN`
4. それ以外 → `PASS`

### severity マッピング（旧→新）

| 旧表記 | 新表記 | 根拠 |
|--------|--------|------|
| Critical | CRITICAL | そのまま |
| High | WARNING | 3段階に統一 |
| Warning | WARNING | 統合 |
| Medium | INFO | 3段階に統一 |
| Suggestion | INFO | 統合 |
| Info | INFO | そのまま |

### confidence

- 範囲: 0-100（整数）
- merge-gate フィルタ閾値: `confidence >= 80`
- specialist は各 finding に必ず confidence を付与する

### category

| 値 | 対象 specialist |
|----|----------------|
| `vulnerability` | worker-security-reviewer, worker-rls-reviewer |
| `bug` | worker-code-reviewer, worker-*-reviewer (conditional) |
| `coding-convention` | worker-code-reviewer |
| `structure` | worker-structure |
| `principles` | worker-principles |
| `architecture-violation` | worker-architecture（pr_diff モード） |
| `architecture-drift` | worker-architecture（plugin_path モード） |
| `chain-integrity-drift` | worker-workflow-integrity |
| `ambiguity` | issue-critic |
| `assumption` | issue-critic |
| `scope` | issue-critic |
| `feasibility` | issue-feasibility |
| `ac-alignment` | issue-pr-alignment（意味的整合性） |
| `ac-alignment-unknown` | issue-pr-alignment（判断不能 AC、INFO のみ） |

## Few-shot 例

### PASS ケース

```
status: PASS

findings: []
```

### files_to_inspect 併記ケース（探索系 specialist）

```json
{
  "status": "WARN",
  "files_to_inspect": [
    "plugins/twl/skills/co-autopilot/SKILL.md",
    "plugins/twl/scripts/chain-runner.sh"
  ],
  "findings": [
    {
      "severity": "WARNING",
      "confidence": 75,
      "file": "plugins/twl/skills/co-autopilot/SKILL.md",
      "line": 42,
      "message": "...",
      "category": "architecture-drift"
    }
  ]
}
```

`files_to_inspect` は optional。reviewer 系 specialist は省略すること。

### FAIL ケース

```
status: FAIL

findings:
- severity: CRITICAL
  confidence: 95
  file: src/auth/session.ts
  line: 42
  message: "セッショントークンが平文で localStorage に保存されている。HttpOnly Cookie を使用すべき"
  category: vulnerability
- severity: WARNING
  confidence: 70
  file: src/auth/session.ts
  line: 58
  message: "セッション有効期限のハードコーディング。環境変数から取得を推奨"
  category: coding-convention
- severity: INFO
  confidence: 60
  file: src/auth/session.ts
  line: 15
  message: "未使用の import: crypto"
  category: coding-convention
```

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

## Model 割り当て

### 判定基準

| Model | 判定基準 | 用途 |
|-------|---------|------|
| **haiku** | 構造チェック・パターンマッチ。LLM 判断が最小限で済む検証タスク | 型検証、テンプレート検証、環境変数チェック |
| **sonnet** | コードレビュー・品質判断・コード生成。LLM の判断力が必要なタスク | コード品質、セキュリティ、E2E生成 |
| **opus** | Controller/Workflow レベルのオーケストレーション。複雑な判断と長期コンテキストが必要 | Controller、Workflow のみ |

### 割り当て一覧

#### haiku (4 件)

| Specialist | 根拠 |
|---|---|
| worker-structure | twl check/audit の結果をパターンマッチで検証 |
| worker-env-validator | .env.example との突合（パターンマッチ） |
| worker-data-validator | データファイルの形式チェック（パターンマッチ） |
| template-validator | Issue テンプレートの必須フィールド検証 |

#### sonnet (23 件)

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

#### opus (0 件 — specialist には使用しない)

Controller と Workflow レベルで使用。specialist には割り当てない（コスト・速度のトレードオフ）。
