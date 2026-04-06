## Context

B-1 で specialist 共通出力スキーマの設計判断（ADR-004）と実装仕様（specialist-output-schema contract）が策定済み。B-6 では、これらを reference コンポーネントとして実体化し、後続の B-5（merge-gate）と C-3（Specialist 移植）が消費可能な形にする。

制約:
- few-shot 例は 1 例のみ（ADR-004: コンテキスト消費 約 150 tokens vs 準拠率 72-90%）
- 出力形式は Markdown 構造化テキスト（JSON ではない — LLM の自然な出力形式に合わせる）
- deps.yaml v3.0 の既存構造を壊さない

## Goals / Non-Goals

### Goals

- `refs/ref-specialist-output-schema.md`: JSON Schema + severity/status 定義 + 消費側パースルール + model 割り当て表を 1 ファイルに集約
- `refs/ref-specialist-few-shot.md`: specialist プロンプト末尾に注入する `## 出力形式（MUST）` セクションのテンプレート
- `deps.yaml` への refs セクション追加
- `output_schema: custom` の除外条件定義

### Non-Goals

- 既存 specialist への few-shot テンプレート適用（C-3 スコープ）
- merge-gate / phase-review のパーサー実装（B-5 スコープ）
- specialist プロンプト自体の作成（C-3 スコープ）

## Decisions

### D1: 出力形式 — Markdown 構造化テキスト

specialist 出力は Markdown 見出し + YAML-like key-value で構造化する。JSON ではなく Markdown を選択した理由:
- LLM は Markdown を自然に生成する（JSON は閉じ括弧の欠落リスクが高い）
- 正規表現でのパースが容易（`status: (PASS|WARN|FAIL)` で十分）
- few-shot 例の可読性が高い

### D2: few-shot テンプレートは FAIL ケースを標準例とする

PASS ケース（`findings: []`）は情報量が少ないため few-shot 例として不適。FAIL ケースを 1 例提供し、CRITICAL + WARNING + INFO の 3 severity を全て含めることで、specialist に出力形式の全容を示す。

### D3: reference コンポーネントの分離

- `ref-specialist-output-schema`: スキーマ定義・パースルール・model 割り当て（消費側 = merge-gate, phase-review）
- `ref-specialist-few-shot`: プロンプト注入テンプレート（消費側 = 各 specialist）

2 つに分離する理由: merge-gate はスキーマ定義のみ必要で few-shot 例は不要。specialist は few-shot テンプレートのみ必要でパースルールは不要。参照の粒度を分けることでコンテキスト消費を最小化する。

### D4: deps.yaml の refs セクション構造

```yaml
refs:
  ref-specialist-output-schema:
    type: reference
    path: refs/ref-specialist-output-schema.md
    description: "specialist 共通出力スキーマ定義"
  ref-specialist-few-shot:
    type: reference
    path: refs/ref-specialist-few-shot.md
    description: "specialist プロンプト用 few-shot テンプレート"
```

`spawnable_by` / `can_spawn` は reference には不要（参照されるのみ）。

### D5: output_schema: custom の除外

deps.yaml の specialist/agent エントリに `output_schema: custom` を指定すると、共通スキーマの few-shot 注入をスキップする。消費側のパース失敗フォールバック（WARNING, confidence=50）は常に適用される。

## Risks / Trade-offs

- **準拠率リスク**: LLM が few-shot 例を無視する可能性（72-90%）。パース失敗フォールバックで安全に fallback するが、CRITICAL finding の見落としリスクあり
- **1 例のみのリスク**: PASS ケースの例がないため、specialist が空の findings を省略する可能性。status 自動導出ルールで対処
- **category 拡張性**: 5 種で固定しているが、将来の specialist 追加で不足する可能性。その場合は ref-specialist-output-schema を更新
