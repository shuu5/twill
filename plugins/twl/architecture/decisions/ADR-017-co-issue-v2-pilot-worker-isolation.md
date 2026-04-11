# ADR-017: co-issue v2 Pilot/Worker プロセス隔離アーキテクチャ

## Status

Proposed (2026-04-12)

## Context

### 現行 co-issue の 2 つの根本欠陥

現行 co-issue は N issue × 3 specialist（critic / feasibility / codex）を親セッションの Task tool で一括並列 spawn する設計を採用している。この設計には 2 つの根本的な欠陥が存在する。

**欠陥 1: specialist sloth（LLM がレビューを省略・まとめ実行する問題）**

N Issue を一括処理する文脈では、LLM がレビューをまとめて 1 回で済ませる、または実質的にスキップする事例が過去に頻発した（インシデント記録: memory hash `c187d16a`, `74be0cdd` 等）。各 Issue の独立したレビューが保証されず、品質の機械的担保が困難。

**欠陥 2: Agent maxTurns truncation（sub-agent が最大ターン数到達で打ち切られる問題）**

2026-04-08 の実測データ（memory hash `4acd64f1`）:
- critic: 1/4 完走（完走率 25%）
- feasibility: 0/4 完走（完走率 0%）
- codex: 4/4 完走（完走率 100%）

この実測により、Task tool ベースの sub-agent 方式は maxTurns truncation に対して無力であることが実証された。gate 機構（IM-7）は対症療法として導入されたが、truncation 自体を防ぐには至らなかった。

### 既存対策の限界

- **gate 機構の追加強化**（代替案 a）: truncation が発生した specialist の結果が「不完全完了」として gate を通過してしまうケースで効果が薄い
- **sub-agent 方式維持**（代替案 b）: 上記実測で失敗が実証済み

## Decision

co-issue v2 として以下のプロセス隔離アーキテクチャを採用する。

### 基本方針

**1 issue = 1 tmux window = 1 独立 cld セッション**

### アーキテクチャ構成

1. **co-issue を Pilot (controller) として維持**
   - N 個の Worker セッションを tmux 経由で spawn する
   - 完了検知・集約・報告を担当

2. **新規 user-invocable workflow `twl:workflow-issue-lifecycle` を Worker として追加**
   - 1 issue の lifecycle（specialist review を含む全フロー）を独立 cld セッションで担当
   - 親セッションの文脈から物理的に隔離されるため specialist sloth が不可能

3. **Handoff はファイル経由**
   - `.controller-issue/<session-id>/per-issue/<index>/` 配下の state file
   - Pilot と Worker 間の通信は全てファイル経由（セッション間分離）

4. **完了検知は polling スクリプト + run_in_background**
   - `Bash(run_in_background=true)` + polling script で Worker 完了を非同期検知

5. **並列数上限: MAX_PARALLEL=3**
   - tmux window 数爆発を防止

## Consequences

### Positive（改善効果）

- **specialist sloth の物理的排除**: LLM の目に他 Issue のコンテキストが入らないため、省略・まとめ実行が構造的に不可能
- **失敗の局所化**: 1 Worker の失敗が他 Issue に波及しない
- **resume 可能性**: state ファイル + deterministic window 名により中断再開が可能
- **maxTurns 予算の独立**: 各 Worker セッションが独立した maxTurns 予算を持つ

### Negative（制約・トレードオフ）

- **critic/feasibility の maxTurns truncation は残る**: 対処として codex review を MUST に昇格する（codex は 4/4 完走の実績あり）
- **tmux window 数増加**: MAX_PARALLEL=3 上限で抑制
- **IM-5/IM-7 の意味変更が必要**（後述）

## Constraint Changes

### IM-5（意味変更: parent レベル → lifecycle workflow セッションローカル不変量に格下げ）

**旧**: 「specialist が実行中のまま後続ステップに進んではならない。全 specialist の結果が揃うまで待機必須」

**新**: 「（親 controller から spawn された場合の制約として）lifecycle workflow セッション**内部**で specialist が実行中のまま aggregate step に進んではならない」

**変更根拠**: co-issue v2 では parent co-issue は specialist を直接 spawn しない。specialist は各 Worker セッション内部で起動されるため、IM-5 は Worker セッション内のローカル不変量となる。parent レベルでの前進禁止制約は自動充足される。

### IM-7（意味変更: 1 層構造 → 2 層構造に分解して維持）

**旧**: 「N Issue × 3 specialist の全完了は機械的に保証しなければならない。`spec-review-session-init.sh` + PreToolUse gate により全 Issue の完了前の forward progression を機械的にブロック」

**新**: 以下の 2 層構造で等価な保証を維持:
- 層 (a): N workers の全 dispatch 完了を parent co-issue controller が保証
- 層 (b): 各 lifecycle workflow セッション内部で N=1 × 3 specialist の完了を `spec-review-session-init.sh 1` + PreToolUse gate で保証

**変更根拠**: specialist の物理隔離（プロセス分離）により、1 Issue あたりの specialist 完了保証（層 b）が独立して機能する。N Issue 全体の保証は層 (a) と層 (b) の組み合わせで維持される。

## Glossary Changes

### Pilot / Worker（context-neutral 拡張）

**旧定義**（Autopilot 文脈専用）:
- Pilot: main/ worktree から実行する制御側。worktree 作成・削除・merge 実行・クリーンアップの専任者
- Worker: Pilot が作成した worktree 内で cld セッションとして起動される実装側。merge 禁止・worktree 操作禁止

**新定義**（context-neutral、上位互換）:
- Pilot: 制御側 cld セッション。Worker セッションを spawn し、集約を行う。autopilot では main worktree 固定、co-issue v2 では session 単位で起動
- Worker: Pilot が tmux 経由で spawn した独立 cld セッション。自律的に単一タスク（autopilot では 1 issue の実装、co-issue v2 では 1 issue の lifecycle）を完遂する

**変更根拠**: 旧定義は autopilot の worktree 管理に特化していたが、co-issue v2 ではプロセス隔離の runtime 用語として「Pilot = 制御側セッション、Worker = Pilot が spawn した独立セッション」という意味で流用する。context-neutral 拡張は旧定義の上位互換であり、既存の autopilot コンテキストの記述と矛盾しない。

## Alternatives Considered

### (a) gate 機構の追加強化

**却下理由**: 2026-04-08 実測（memory hash `4acd64f1`）で gate だけでは maxTurns truncation に無力であることが実証済み。truncation が発生した specialist の結果が「不完全完了」として gate を通過するケースへの対処ができない。

### (b) sub-agent（Task tool）方式維持

**却下理由**: 同上の実測データで失敗が実証済み。critic=1/4, feasibility=0/4 という完走率は許容不能。

### (c) プロセス隔離（採用）

tmux + 別 cld セッションで物理的に分離することで、specialist sloth と maxTurns truncation の両方を構造的に解決する。

## References（補助情報）

Context セクションに要点は埋め込み済み。以下は補助参照:

- memory hash `4acd64f1`: 2026-04-08 実測データ（critic=1/4, feasibility=0/4, codex=4/4）
- memory hash `c187d16a`, `74be0cdd`: specialist sloth インシデント記録
- memory hash `1e7f4c21`, `df6a1416`: 追加背景
- `plugins/twl/refs/ref-types.md` L13, L138: `co-` prefix は controller 専用（変更不要）
- ADR-014: `ADR-014-pilot-driven-workflow-loop.md`（Pilot/Worker 役割の原典）
- ADR-016: `ADR-016-test-target-real-issues.md`（直前の ADR、2026-04-11 merge）
