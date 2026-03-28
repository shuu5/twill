---
name: dev:spec-scaffold-tests
description: OpenSpec ScenarioからBDDテストを自動生成（Unit/Integration）
type: specialist
model: sonnet
effort: high
maxTurns: 40
tools: [Bash, Read, Glob, Grep, Write, Edit]
---

# /dev:spec-scaffold-tests コマンド

OpenSpec提案内のScenarioを解析し、テストファイルとtest-mapping.yamlを自動生成します。

## 引数

- `<change-id>`: OpenSpec提案ID（必須）

## 前提条件

- `openspec/changes/<change-id>/specs/` が存在すること
- specs内に`#### Scenario:`形式でScenarioが定義されていること

## 実行フロー

### 1. 入力確認

- change-id バリデーション: `^[a-zA-Z0-9_-]+$` のみ許可（パストラバーサル防止）
- `openspec/changes/<change-id>/specs/` の存在確認
- 既存 `test-mapping.yaml` がある場合は上書き確認

### 2. Scenarioパース

`specs/**/*.md`から以下のパターンを抽出:

```markdown
#### Scenario: <scenario-name>
WHEN: <条件>
THEN: <期待結果>
LLM_CRITERIA:
  - <基準1>
  - <基準2>
```

**LLM_CRITERIA検出**: `LLM_CRITERIA:` ヘッダーが WHEN/THEN 直後に存在する場合、続くインデント付きリスト項目（`  - ` プレフィックス）を全て抽出。存在しなければ `criteria` は空配列。

**終端条件**: 空行 / 次の `#### Scenario:` / インデントなし行

**サニタイズルール**: criteria項目をコメント埋め込み時:
- `*/` → `*\/`、`"""` / `'''` → バックスラッシュエスケープ、改行 → `\n`

抽出結果の構造:
```
{ id, name, when, then, criteria[], source_file, source_line, requirement }
```

### 3. プロジェクトタイプ判定

| ファイル | 言語 | フレームワーク |
|---------|------|---------------|
| `package.json` | JS/TS | Jest（`jest`あり）/ Vitest（`vitest`あり）/ デフォルトJest |
| `DESCRIPTION` | R | testthat |
| `pyproject.toml` / `setup.py` | Python | pytest |

### 4. テストファイル生成

各Scenarioに対してBDDスタイルのテストを生成。AIがWHEN/THENを解釈して実装コードを生成する（プレースホルダーではなく実コード）。不明な場合のみTODOコメントを残す。

| フレームワーク | ファイルパス | テスト構造 |
|--------------|------------|-----------|
| Jest/Vitest | `tests/scenarios/<requirement-slug>.test.ts` | `describe('<Requirement>') > it('should ... WHEN ... THEN ...')` |
| pytest | `tests/scenarios/test_<requirement_slug>.py` | `class Test<Requirement> > def test_<scenario>_when_<w>_then_<t>` |
| testthat | `tests/testthat/test-<requirement-slug>.R` | `test_that("<scenario> WHEN <w> THEN <t>")` |

### 5. LLM-evalテストファイル生成

`criteria` が空でないScenarioに対して、LLM-evalスタブテストを生成。

| フレームワーク | ファイルパス | テスト構造 |
|--------------|------------|-----------|
| Jest/Vitest | `tests/scenarios/<slug>.llm-eval.test.ts` | `describe('<Requirement> [LLM-eval]') > it('LLM_CRITERIA: <scenario>')` |
| pytest | `tests/scenarios/test_<slug>_llm_eval.py` | `class Test<Requirement>LlmEval > def test_llm_criteria_<scenario>` |
| testthat | `tests/testthat/test-<slug>-llm-eval.R` | `test_that("LLM_CRITERIA: <scenario>")` |

テスト内にはWHEN/THEN + LLM_CRITERIAの各基準をコメントとして埋め込む。

### 5.5. affected_by 自動推定（LLM-eval Scenario のみ）

1. CLAUDE.md の `## LLM依存ファイル` セクションからファイルパスリストを取得（未定義時はスキップ）
2. Scenario名・WHEN/THEN・LLM_CRITERIAからキーワード抽出
3. LLM依存ファイルの関数名・定数名とキーワードを照合
4. 関連ファイル（:関数名）を affected_by に設定

**コメント付与**: 自動推定には `# auto-inferred: review recommended` を付与。
**手動保護**: 既存 affected_by に `# auto-inferred` コメントなし → 上書きしない。

### 6. test-mapping.yaml生成

`openspec/changes/<change-id>/test-mapping.yaml` を生成:

```yaml
change_id: <change-id>
generated_at: <ISO8601>
test_framework: jest | pytest | testthat
scenarios:
  - id: "<slugified>"
    name: "<Scenario名>"
    spec_file: "specs/<cap>/spec.md"
    spec_line: <行番号>
    requirement: "<Requirement名>"
    test_file: "<生成テストパス>"
    test_name: "<テスト名>"
    type: unit | llm-eval
    criteria: []          # llm-eval時のみ
    affected_by: []       # llm-eval時のみ（オプション）
    status: pending       # pending | passing | failing
    last_run: null
    failure_reason: null
```

## E2Eテスト自動連携

### E2E Scenario検出キーワード

| キーワード | 判定 |
|-----------|------|
| `E2E` `Playwright` `browser` | E2Eテスト |
| `GIVEN the application is running` / `GIVEN the page is loaded` | E2Eテスト |
| `WHEN user clicks` / `WHEN user navigates` | E2Eテスト |

**除外ルール**: `LLM_CRITERIA:` を含むScenarioはE2E検出しない（LLM-eval優先）。

### 自動フロー

E2E Scenario検出時 → `/dev:e2e-generate` を直接呼び出し → 4層検証パターン強制適用。

## 注意事項

- 既存テストファイルは上書きしない（新規追加のみ）
- test-mapping.yamlは提案ごとに管理（アーカイブ時に一緒に移動）
- Scenario形式不正はスキップしてログに記録

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
