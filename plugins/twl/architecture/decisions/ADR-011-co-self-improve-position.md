# ADR-011: co-self-improve の位置づけ — 能動的 Live Observation Controller

## Status
Accepted

## Context

既存の Self-Improve Context は完全受動型であり、co-autopilot の後処理（retrospective）として統合されている（ADR-002）。パターン検出と ECC 照合は autopilot Phase 完了後にのみ起動する。

直前の Pseudo-Pilot 実証（21 Issue 連続完遂）で、manual verify ループの価値と限界が実証された。Pilot がリアルタイムで Worker を観察し介入する行為は、autopilot の品質に直接寄与するが、Pilot の負荷が高く、人間の注意力に依存する。

#171（Pilot active review framework）は in-process での Pilot 能動評価を強化するが、これはあくまで autopilot Phase 内の補強であり、out-of-process での observation（別セッションからの観察）とは別レイヤーである。

実 twill main repo を試行錯誤の場にするのはリスクが高い。テストプロジェクト（隔離 worktree）で安全に試行錯誤し、検出した問題を Issue として本プロジェクトに還元する仕組みが必要である。

### ADR-002 との関係

ADR-002 は「旧 self-improve controller を co-autopilot に吸収する」決定であり、「受動的 self-improve の独立 controller 化を否定」するものである。本 ADR の「能動的 observation の独立 controller 化」とは対象が異なる:

- ADR-002 の対象: autopilot 後処理としてのパターン検出（受動的・事後的）
- 本 ADR の対象: ライブセッション観察とテストプロジェクト管理（能動的・リアルタイム）

両者は概念レイヤーが異なり、両立する。

## Decision

### 1. co-self-improve を 6 個目の controller として新設する

co-autopilot / co-issue / co-project / co-architect / co-utility に続く 6 個目の controller。カテゴリは **Observation**（Implementation でも Non-implementation でもない新カテゴリ）。

### 2. 新しい Bounded Context「Live Observation Context」を定義する

`plugins/twl/architecture/domain/contexts/observation.md` で定義。短称は Observation Context。

### 3. 既存 Self-Improve Context は存続する

既存 Self-Improve Context（workflow-self-improve）の役割を「内省的 retrospective」と再定義する。co-self-improve は「能動的 live observation」と定義する。両者の責務は重ならない:

| 側面 | Self-Improve (受動) | Live Observation (能動) |
|------|---------------------|------------------------|
| トリガー | autopilot Phase 完了時 | ユーザートリガー / スケジュール |
| 対象 | 完了済みセッションの結果 | 実行中セッション / テストプロジェクト |
| 手段 | パターン検出 + ECC 照合 | ライブ観察 + 問題検出 + Issue 起票 |
| controller | co-autopilot 内 | co-self-improve（独立） |

## Consequences

### Positive
- 能動的 observation と受動的 retrospective の責務が明確に分離される
- テストプロジェクトによる安全な試行錯誤が可能になる
- ADR-002 の設計判断を壊さず、新しいレイヤーを追加できる

### Negative
- Controller 数が 4 → 6 に増加（co-utility 含む。vision.md / CLAUDE.md の既存不整合も同時修正）
- 新しい Bounded Context の追加による architecture spec の複雑化

### Mitigations
- co-self-improve の責務を observation に限定し、受動的 self-improve（workflow-self-improve）には干渉しない
- vision.md の Controller 操作カテゴリに Observation を追加し、Implementation / Non-implementation との区別を明示
