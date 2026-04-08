# ADR-0007: chain SSOT — chain.py CHAIN_STEPS と deps.yaml chains の関係定義

## Status

Accepted

## Context

chain の定義が3箇所に存在し、乖離が検出されない状態だった:

1. **`cli/twl/src/twl/autopilot/chain.py` の `CHAIN_STEPS`** — chain-runner が機械的に状態記録・スキップ判定するステップの順序リスト
2. **`plugins/twl/deps.yaml` の `chains:`** — ワークフロー全体の概念的構造（LLM ステップを含む）
3. **`plugins/twl/scripts/chain-steps.sh` の `CHAIN_STEPS`** — bash ベースの同期コピー

両者の関係はドキュメント化されておらず、以下の既知の乖離が存在していた:

| ステップ | chain.py | deps.yaml chains | 理由 |
|---|---|---|---|
| `arch-ref` | ✅ | ❌ | chain-runner が機械的実行するが概念チェーンに含めない設計 |
| `change-id-resolve` | ✅ | ❌ | 同上 |
| `check` | ✅ | ❌ | 同上 |
| `post-change-apply` | ✅ | ❌ | LLM ステップだが workflow-test-ready 内部で記録のみ |
| `phase-review` | ❌ | ✅ | LLM composite ステップ（chain-runner 不使用）|
| `scope-judge` | ❌ | ✅ | LLM composite ステップ |
| `merge-gate` | ❌ | ✅ | LLM composite ステップ |
| `auto-merge` | ❌ | ✅ | script ステップだが chain-runner 外部で実行 |
| `fix-phase` | ❌ | ✅ | LLM composite ステップ |
| `post-fix-verify` | ❌ | ✅ | LLM composite ステップ |
| `warning-fix` | ❌ | ✅ | LLM composite ステップ |
| `e2e-screening` | ❌ | ✅ | LLM composite ステップ |
| `pr-cycle-analysis` | ❌ | ✅ | LLM composite ステップ |
| `worktree-create` | ❌ | ✅ | script だが chain-runner.sh 経由（chain.py 移管前） |
| `project-board-status-update` | ❌ | ✅ | `board-status-update` として chain.py に存在 |
| `ac-verify` | ✅ (追加) | ✅ | LLM マーカー（chain-runner は記録のみ） |

## Decision

### 1. 2レイヤーの責務分離

**chain.py CHAIN_STEPS**（SSOT: 機械的ステップ）:
- chain-runner（Python/bash）が状態記録・スキップ判定・遷移検証を行うステップ
- `next-step` コマンドで返される候補はこのリストから
- `is_quick` によるスキップもここで管理

**deps.yaml chains:**（概念的ワークフロー全体）:
- LLM が Skill tool で実行するステップを含む
- 各チェーンの設計意図を表す
- `dispatch_mode` フィールドで各ステップの実行方式を明記

### 2. dispatch_mode フィールド

deps.yaml の chain 関連コンポーネントには `dispatch_mode` を必須とする:

| 値 | 意味 |
|---|---|
| `runner` | chain-runner（Python または bash）が機械的に実行。CHAIN_STEPS に含まれ、chain-runner.sh の case 文で処理される |
| `llm` | LLM（Skill tool）が実行。chain-runner は記録のみ。CHAIN_STEPS に含まれてもよい（ac-verify 等） |
| `trigger` | chain-runner.sh が処理するが CHAIN_STEPS 外の条件付き実行（worktree-create, auto-merge 等）|

### 3. 整合性規則（twl chain validate で検証）

- deps.yaml chains に存在するが `dispatch_mode` がないコンポーネント → warning
- deps.yaml chains に存在し `dispatch_mode: runner` だが CHAIN_STEPS にない → critical
- deps.yaml chains に存在し `dispatch_mode: llm` だが CHAIN_STEPS にある → info（正当）
- chain-runner.sh case 文に存在するステップで CHAIN_STEPS に含まれないもの → warning

### 4. chain-steps.sh の位置付け

`chain-steps.sh` は chain.py の bash 向けミラー。chain.py CHAIN_STEPS が SSOT であり、chain-steps.sh は chain.py と常に同期する。差異が生じた場合は `twl chain validate` が検出する。

## Consequences

- chain.py と deps.yaml の乖離が `twl chain validate` で継続的に検証される
- 新規ステップ追加時は dispatch_mode の宣言が必要になる
- chain-steps.sh と chain.py の差異は発生時に即時検出される
