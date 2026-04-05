## Context

co-issue の分割判断で極小 Issue が頻出する。現在のフル chain は setup(6 steps) + test-ready(4 steps) + pr-cycle(12 steps) = 22 ステップで構成されており、1行修正でも全ステップを通過する。軽量 chain で品質を維持しつつトークン効率を改善する。

既存の deps.yaml には `setup` chain（type A）と `pr-cycle` chain（type B）が定義済み。chain-runner.sh の `step_init` 関数がブランチ状態と OpenSpec 状態から `recommended_action` を決定する。

co-issue には `--quick` フラグ（Phase 3b specialist スキップ）が既に存在する。これは Issue 作成時の効率化であり、Worker 側の軽量 chain とは別概念。

## Goals / Non-Goals

**Goals:**

- co-issue Phase 2 に quick 判定基準を追加し、小規模 Issue を自動検出する
- co-issue Phase 3b specialist に quick 分類の妥当性検証を追加する
- co-issue Phase 4 で `quick` ラベルを GitHub Issue に付与する
- workflow-setup init で `quick` ラベルを検出し、軽量 chain に分岐する
- 軽量 chain を deps.yaml に定義する（7 ステップ以下）
- merge-gate による品質保証を軽量 chain でも維持する

**Non-Goals:**

- 機械的ステップの script 化（#119 の責務）
- バッチ処理の最適化
- 既存 Issue への遡及的 quick ラベル付与
- --quick フラグの動作変更（specialist スキップは現行通り）

## Decisions

### D1: quick 判定は co-issue Phase 2 で初期推定、Phase 3b で検証

Phase 2 で Issue body の記述から quick 候補を推定し、Phase 3b の specialist が実コードベースで検証する。3段階（推定 → 検証 → ユーザー承認）で誤分類を防ぐ。

### D2: quick ラベルは GitHub ラベルとして伝達

co-issue → autopilot-launch → worker の情報伝達は GitHub ラベル経由。状態ファイルや環境変数ではなく、GitHub API で検出可能な永続的メタデータを使う。

### D3: 軽量 chain は deps.yaml に `quick-setup` として定義

```yaml
quick-setup:
  type: "A"
  description: "軽量開発ワークフロー（quick ラベル付き Issue 用）"
  steps:
    - init
    - worktree-create
    - project-board-status-update
```

軽量 chain は setup の短縮版。OpenSpec（opsx-propose, ac-extract）をスキップし、worktree 作成後は直接実装に入る。pr-cycle は `merge-gate` 単体で代替（merge-gate の動的レビュアー構築が diff サイズに適応済み）。

### D4: init スクリプトで quick 検出後の分岐

chain-runner.sh の `step_init` に quick ラベル検出を追加。Issue 番号が渡された場合に `gh issue view --json labels` で確認し、`is_quick: true` を JSON 出力に含める。workflow-setup SKILL.md が `is_quick` を見て chain を切り替える。

### D5: --quick フラグと quick ラベルの棲み分け

| 概念 | スコープ | 効果 |
|------|---------|------|
| `--quick` フラグ | co-issue 実行時 | Phase 3b specialist スキップ |
| `quick` ラベル | Worker 実行時 | 軽量 chain で処理 |

`--quick` フラグ使用時は quick ラベルを暗黙付与しない（specialist 未検証のため）。

### D6: merge-gate は軽量 chain でも必須

merge-gate の動的レビュアー構築は diff サイズに応じてレビュー深度を調整するため、小規模変更でも適切な品質チェックが行われる。phase-review, scope-judge, fix-phase 等は省略可能だが、merge-gate は省略しない。

## Risks / Trade-offs

### R1: quick 誤分類リスク（中）

小規模に見えて実は影響範囲が広い変更を quick と誤判定する可能性がある。Phase 3b の specialist 検証で軽減するが、specialist 自体の精度に依存する。

**軽減策**: specialist が `quick-classification: inappropriate` finding を出した場合、quick ラベルを付与しない。

### R2: 軽量 chain のテスト不足リスク（低）

OpenSpec とテストスキャフォールドをスキップするため、テスト漏れの可能性がある。ただし対象は ~20行以下の変更であり、merge-gate の動的レビュアーがカバーする。

### R3: 3リポジトリへのラベル作成の運用負荷（低）

`quick` ラベルを loom-plugin-dev, loom, ubuntu-note-system の 3 リポジトリに作成する必要がある。一度きりの作業だが手順の明文化が必要。
