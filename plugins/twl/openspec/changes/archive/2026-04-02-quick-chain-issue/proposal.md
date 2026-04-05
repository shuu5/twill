## Why

co-issue の分割判断で「責務上分離すべきだが実装は極小」な Issue が頻出する（例: 5行修正、1行追加）。フル chain（24 ステップ）では 1行修正に ~200k tokens を消費しており、軽量 chain で品質を維持しつつトークン効率を改善する必要がある。

## What Changes

- co-issue Phase 2 に quick 判定基準を追加（変更ファイル 1-2 個 AND ~20行以下）
- co-issue Phase 3b specialist（issue-critic, issue-feasibility）に quick 分類妥当性検証を追加
- co-issue Phase 4 で `--label quick` 付与
- workflow-setup init で `quick` ラベル検出 → 軽量 chain に分岐
- 軽量 chain（7 ステップ）の定義と deps.yaml chains セクションへの登録
- `quick` GitHub ラベルの作成（3 リポジトリ）

## Capabilities

### New Capabilities

- **quick 判定**: co-issue が Issue の複雑度を判定し、小規模 Issue に `quick` ラベルを推奨
- **specialist 検証**: issue-critic / issue-feasibility が quick 分類の妥当性を検証
- **軽量 chain**: init → worktree → 直接実装 → commit → push → PR → merge-gate の 7 ステップで処理
- **自動分岐**: workflow-setup init が quick ラベルを検出し、軽量 chain に自動切替

### Modified Capabilities

- **co-issue Phase 2**: quick 判定基準の追加
- **co-issue Phase 3b**: quick-classification カテゴリの findings 追加
- **co-issue Phase 4**: quick ラベル付与ロジック追加
- **workflow-setup init**: quick ラベル検出と分岐ロジック追加

## Impact

- **co-issue SKILL.md**: Phase 2, 3b, 4 の記述変更
- **workflow-setup SKILL.md**: init ステップの分岐条件追加
- **deps.yaml**: 軽量 chain 定義の追加
- **init スクリプト**: quick ラベル検出ロジック追加
- **既存 --quick フラグ**: specialist スキップとの棲み分け整理（--quick は specialist スキップ、quick ラベルは Worker 軽量 chain）
