# diagnose: プラグイン問題診断

## 目的
既存ATプラグインの問題を包括的に診断する。

## 入力
- プラグインのパス（例: `~/ubuntu-note-system/claude/plugins/dev`）

## 手順

### 1. 構造検証
```bash
cd {plugin-path}
twl check
twl validate
```

### 2. frontmatter 整合性チェック
各ファイルを Read で確認:
- name フィールドが `t-{name}:{component}` 形式か
- type に応じた固有フィールドがあるか
- allowed-tools / tools が適切か

### 3. 5原則チェック（workerプロンプト品質）
agents/ 配下の team-worker ファイルを読み込み、以下を評価:

#### 完結 (Self-Contained)
- [ ] タスクの目的が明記されている
- [ ] 成功条件が定義されている
- [ ] 報告方法が記載されている

#### 明示 (Explicit)
- [ ] 型・ツール制約が冒頭宣言されている
- [ ] 禁止事項が明記されている

#### 外部化 (Externalize)
- [ ] per_phase時に外部コンテキスト手段が定義されている

#### 並列安全 (Parallel-Safe)
- [ ] 同一ファイル競合リスクがない

#### コスト意識 (Cost-Aware)
- [ ] model が明示されている
- [ ] 不要に高価なモデルを使っていない

### 4. アーキテクチャパターン評価
ref-skill-arch-patterns を参照し、5パターンの適用状態を評価:

- **AT並列レビュー**: team-phase + parallel: true + worker 構成の確認
- **パイプライン**: controller の calls 順序と依存関係の確認
- **ファンアウト/ファンイン**: タスク分割→並列→統合の構造確認
- **Context Snapshot**: 4ステップ以上でのsnapshot導入有無
- **Subagent Delegation**: WebFetch/WebSearch コマンドの specialist 委任状態

横断チェック:
- lifecycle 妥当性（per_phase + external_context）
- max_size 整合性
- パターン組合せ安全性

### 5. orphan ノード検出
```bash
twl orphans
```
- 上流から到達不能なノードを検出
- orphan は Critical として報告

### 5.5. deep-validate チェック
```bash
twl audit
```

以下のカテゴリで問題を検出:
- `[controller-bloat]` Warning/Critical — controller 行数超過（120/200行）
- `[controller-inline]` Warning — controller にインライン実装
- `[dead-weight]` Info — 非実行的ドキュメント
- `[tools-mismatch]` Warning — frontmatter vs body ツール不一致
- `[tools-unused]` Info — frontmatter 宣言あり body 未使用
- `[ref-placement]` Warning — reference が消費者でなく中間者に宣言

### 6. 診断レポート出力
問題の重要度（Critical / Warning / Info）で分類して表示。

## Context Snapshot（controller-improve 経由の場合）
controller-improve から呼ばれる場合、phase-diagnose が並列実行を担当するため、
このコマンドは standalone（単体）での使用向け。
standalone 使用時も、snapshot_dir が指定されている場合は結果を
`{snapshot_dir}/01-diagnose-results.md` に Write する。

## 出力
診断レポート:
- Critical: 即座に修正が必要
- Warning: 改善推奨
- Info: 参考情報
