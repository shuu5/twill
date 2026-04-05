# 設計経緯転記

旧 dev plugin (claude-plugin-dev) の重要な設計判断経緯を記録。
plugin-dev の設計根拠として参照される。

## 1. merge-gate 2パス統合

**転記元**: claude-plugin-dev `skills/co-autopilot/SKILL.md`, `commands/merge-gate.md`

### 旧設計（2パス）

claude-plugin-dev では merge-gate に standard パスと plugin パスの 2種類が存在した。
standard パスは通常のコードレビュー、plugin パスは deps.yaml 整合性チェックを追加で実行。

### 統合判断の理由

- 2パス分岐により条件分岐が増殖し、merge-gate-init.sh が複雑化
- plugin パスのチェック項目（deps.yaml 整合性、型ルール）は standard パスでも有用
- twl CLI の登場により、構造チェックを外部ツールに委譲可能になった

### 新設計（動的構築）

plugin-dev では変更ファイルから reviewer を動的に構築。パス分岐を廃止し、
全レビューを並列 Task spawn で実行。twl validate/check が構造チェックを担当。

## 2. deps.yaml 競合 Phase 分離

**転記元**: claude-plugin-dev `skills/co-autopilot/SKILL.md`, `architecture/ADR-003.md`

### 問題

autopilot の Phase 並列実行時に、複数 worker が同時に deps.yaml を編集すると
git conflict が発生する。特に新コンポーネント追加時にマージ不可能な競合が頻発。

### 旧設計の対策

不変条件 H（deps.yaml 変更排他性）を導入。同一 Phase 内で deps.yaml を変更する
Issue は 1 つのみに制限。Phase 計画時に deps.yaml 変更 Issue を検出し、
別 Phase に分離する。

### 新設計での継続

plugin-dev でも不変条件 H を維持。autopilot-plan.sh が依存グラフ構築時に
deps.yaml 変更を含む Issue を検出し、同一 Phase に複数配置しない。

## 3. autopilot 不変条件の由来

**転記元**: claude-plugin-dev `skills/co-autopilot/SKILL.md`, `architecture/ADR-001.md`

### 経緯

2026年2-3月の autopilot 運用で発生した障害から9件の不変条件を策定:

| 不変条件 | 由来となった障害 |
|----------|----------------|
| A: 状態一意性 | 複数 worker が同一 Issue を同時処理し状態不整合 |
| B: Worktree 削除 Pilot 専任 | Worker が自身の worktree を削除し CWD 消失 |
| C: Worker マージ禁止 | Worker の squash merge で他 worker のベースが壊れる |
| D: 依存先 fail skip 伝播 | 依存先 Issue 失敗後に依存側が不整合な状態で実行 |
| E: merge-gate リトライ制限 | merge-gate の無限リトライでAPIクォータ枯渇 |
| F: rebase 禁止 | rebase によるコミット消失で worker 状態不整合 |
| G: クラッシュ検知保証 | tmux ペイン消失を検知できず zombie worker 発生 |
| H: deps.yaml 変更排他性 | 並列 Phase で deps.yaml 競合（上記参照） |
| I: 循環依存拒否 | 依存グラフの循環でデッドロック |

### 新設計での実装

plugin-dev では全9件を autopilot-invariants.bats で自動検証。
スクリプトレベルで不変条件違反を検出し、実行前にブロックする設計。
