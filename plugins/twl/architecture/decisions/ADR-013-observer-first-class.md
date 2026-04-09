# ADR-013: Observer の First-Class 昇格 — メタ認知レイヤーの独立型化

## Status
Accepted

## Context

### 背景

ADR-011 は co-self-improve を「能動的 Live Observation Controller」として定義し、Observation カテゴリを新設した。しかし ADR-011 の Decision 1 は「co-self-improve を 6 個目の *controller* 型として新設する」であり、Observer を controller と同等に扱っている。

2026-04-09 の 27 件 Issue 一括実行セッションで、autopilot のメタ認知不能が実証された。このセッションで **ユーザーが Observer として行った介入**は以下の規模に達した:

| 介入種別 | 回数 |
|----------|------|
| PR 作成・マージ管理 | ~15 回 |
| state 遷移（force-done, emergency bypass 含む） | ~20 回 |
| Wave 管理（phase計画・順序変更） | 複数回 |
| 並行セッション調整（Worker クラッシュ回復） | 複数回 |

これらの介入は現在の co-self-improve（ADR-011）の権限範囲外である。co-self-improve は read-only 観察 + Issue 起票のみ担当し、state を直接書き換えたり、orchestrator の判断を上書きする権限を持たない。

### 問題の本質

autopilot は単一セッション内の Worker 制御を担うが、**セッション横断的なメタ認知**（複数 Worker の状態把握、Wave 全体の進捗管理、障害時の戦略的判断）を行う層が存在しない。現状この役割はユーザーが手動で担っている。

Observer（ユーザーまたは将来の自律的 Observer エージェント）は controller を *監視・調整* する行為を行っており、これは controller と同一階層に置くべきではない。

### ADR-002 との関係

ADR-002 は「旧 self-improve controller を co-autopilot に吸収する」決定であり、**受動的・事後的**なパターン検出が対象。本 ADR が定義する observer 型は**能動的・リアルタイム**な監視・介入であり、ADR-002 の吸収対象とは概念レイヤーが異なる。両者は両立する。

### ADR-011 との関係

ADR-011 の Decision 1（co-self-improve は controller 型）は本 ADR では否定しない。co-self-improve は引き続き controller 型として存在する。本 ADR は「Observer が上位メタ認知層として controller を監視・調整できる新型 observer を定義する」ものであり、ADR-011 を **supersede せず extend** する。

```
ADR-011:  co-self-improve = controller (Observation カテゴリ)
ADR-013:  observer 型 = controller の上位監視層（新概念）
           ↑ co-self-improve は observer の「テスト実行 arm」として位置づけ直し
```

## Decision

### Decision 1: `observer` 型の新設

`cli/twl/types.yaml` に 8 個目の型として `observer` を追加する。controller とは別型であり、controller を監視・調整する上位権限を持つ。

```yaml
observer:
  section: skills
  can_supervise: [controller]
  can_spawn: [workflow, atomic, composite, specialist, reference, script]
  spawnable_by: [user]
  token_target:
    warning: 2000
    critical: 3000
```

observer 型の特徴:
- `can_supervise: [controller]` — controller の状態を読み書き可能
- `spawnable_by: [user]` — ユーザーからのみ起動（自律起動は将来拡張）
- controller より上位の階層に位置するが、autopilot の実行制御には干渉しない

### Decision 2: co-self-improve の C) 階層化

co-self-improve（controller 型、ADR-011）を observer 型との **C) 階層化** で再定義する:

| 役割 | 型 | 位置づけ |
|------|-----|----------|
| Observer（上位） | observer | セッション横断的なメタ認知・Wave 管理・戦略的介入 |
| co-self-improve（下位） | controller | Observer の「テスト実行 arm」— ライブ観察・Issue 起票 |

Observer は co-self-improve を spawn し、その結果を統合してより高次の意思決定を行う。co-self-improve 単独では実行できない「state 書き換え」「orchestrator 判断上書き」「Wave 再計画」は observer 型の権限スコープに属する。

### Decision 3: 3 層介入プロトコル（Auto/Confirm/Escalate）

Observer の介入は以下の 3 層で分類する。各層の **判断基準**:

#### Auto（自動介入）
**条件**: Worker が明確な失敗状態（status=failed）かつ回復手順が確立されている場合
- 例: non_terminal_chain_end → force-done + PR 確認
- 例: crash-detected → window 再起動
- **制約**: 破壊的操作（worktree 削除、force push）は含まない

#### Confirm（確認後介入）
**条件**: 状態が曖昧または複数の回復戦略が存在する場合
- 例: Worker が長時間 idle（15分以上）だが status=in-progress
- 例: Phase 計画の変更が必要（依存関係の追加・削除）
- **制約**: 必ずユーザーに意図を提示してから実行

#### Escalate（エスカレーション）
**条件**: Observer 自身では判断不能、または影響範囲が広い場合
- 例: main ブランチの整合性破壊リスク
- 例: 複数 Worker に影響する設計上の問題
- 例: ADR 変更を要する根本的な設計課題の発見
- **制約**: 実行せずユーザーに委譲。Issue 化推奨

## Consequences

### Positive
- autopilot のメタ認知不能問題に対し、概念的な解決フレームワークが得られる
- Observer 介入の分類基準が明確化され、「何は自動化できるか」の議論基盤が生まれる
- ADR-011 の co-self-improve 設計を壊さず、上位レイヤーを追加できる
- 将来の自律的 Observer エージェント実装に向けた型システムの基盤が整う

### Negative
- types.yaml に 8 型目が追加され、型システムの複雑性が増加
- `can_supervise` という新フィールドは既存型の `can_spawn` と意味論が異なり、ドキュメント整備が必要
- observer 型の実装（co-observer コンポーネント）は本 ADR のスコープ外であり、後続 Issue が必要

### Mitigations

#### type system への影響（後続 Issue で実装）
- `cli/twl/types.yaml` に observer 型と `can_supervise` フィールドを追加（スキーマ拡張 Issue）
- `deps.yaml` に `supervises` フィールドを追加し、observer → controller の監視関係を宣言可能にする（スキーマ拡張 Issue）

#### ADR-011 との整合
- co-self-improve の `type` フィールドは `controller` のまま維持（ADR-011 Decision 1 を尊重）
- `deps.yaml` の co-self-improve エントリに `supervised_by: co-observer`（または相当フィールド）を追加することで階層関係を表現

#### vision.md / observation.md の更新
- Controller カテゴリの記述に observer 型との階層関係を追記（後続 Issue）
- 3 層介入プロトコルの詳細仕様は observation.md で展開（後続 Issue）
