---
type: composite
tools: [Bash, Agent, Skill, Task, Read]
effort: medium
maxTurns: 30
---
# テスト生成（統合）

テスト生成を統合管理する composite コマンド。
Scenario 種別に応じて specialist を適切に呼び出し。

## 使用方法

```
/twl:test-scaffold <change-id> [--type=<type>] [--coverage=<level>] [--e2e-mode=<mode>]
```

| オプション | 値 | デフォルト |
|-----------|-----|----------|
| `--type` | `unit`, `e2e`, `llm-eval`, `all` | `all` |
| `--coverage` | `happy-path`, `edge-cases` | type 依存 |
| `--e2e-mode` | `mock`, `deploy`, `auto` | `auto` |

## 実行フロー

### 1. Scenario 解析

`deltaspec/changes/<change-id>/specs/` を確認し、Scenario を分類:

| キーワード | 分類 |
|-----------|------|
| `LLM_CRITERIA:` ブロックを含む | LLM-eval テスト |
| `E2E` `Playwright` `browser` | E2E テスト |
| `GIVEN the application is running` | E2E テスト |
| `WHEN user clicks` `WHEN user navigates` | E2E テスト |
| それ以外 | Unit/Integration テスト |

**優先順位**: `LLM_CRITERIA:` 検出が最優先。

### 2. Unit/Integration テスト生成

Unit/Integration Scenario が検出された場合、Task tool で specialist を起動:

```
Task(subagent_type="twl:spec-scaffold-tests", prompt="<change-id>...")
```

### 3. E2E テスト生成

E2E Scenario が検出された場合:

#### E2E モード判定

| 指定値 | 動作 |
|--------|------|
| `mock` | モックモード（`page.route()` + `route.fulfill()`） |
| `deploy` | デプロイモード（実バックエンド通信、5層検証） |
| `auto` | playwright.config.ts の webServer 設定で自動判定 |

```
Task(subagent_type="twl:e2e-generate", prompt="<change-id> --e2e-mode=<mock|deploy>...")
```

### 4. test-mapping.yaml 統合

両方の結果を統合してマッピングファイル更新。

## specialist 呼び出し（MUST）

specialist は **Task tool** で呼び出す。Skill tool は使用不可。

**specialist 未実装時の fallback**: `twl:spec-scaffold-tests` または `twl:e2e-generate` の subagent_type が利用不可の場合、`general-purpose` Agent として同等のプロンプトを渡して実行する。

## 禁止事項（MUST NOT）

- Skill tool で specialist を呼び出してはならない
- 両方の specialist を並列呼び出ししてはならない（順次実行）

## 後方互換（MUST）

`--e2e-mode=integration` 指定時:
1. 警告表示: `--e2e-mode=integration は非推奨。deploy モードとして実行します`
2. `--e2e-mode=deploy` に変換して実行
