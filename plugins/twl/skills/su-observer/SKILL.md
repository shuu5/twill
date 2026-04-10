---
name: twl:su-observer
description: |
  Supervisor メタ認知レイヤー（ADR-014）。
  プロジェクトに常駐し、controller セッションを監視・介入する。
  3 層介入プロトコル（Auto/Confirm/Escalate）に従って問題を検出・分類・対処する。
  co-self-improve へのテスト委譲、Wave 管理、compaction 知識外部化も担う。

  Use when user: says su-observer/supervisor/介入/intervention/監視/observer,
  wants to monitor a running controller session,
  wants to intervene in a Worker's state,
  wants to manage Wave planning or project-level coordination,
  wants to delegate test scenario execution to co-self-improve.
type: supervisor
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
---

# su-observer

プロジェクト常駐のメタ認知レイヤー。全 controller セッションを監視し、問題を検出したとき
`refs/intervention-catalog.md` の 3 層分類（Auto/Confirm/Escalate）に基づいて介入する。
テストシナリオ実行は co-self-improve に委譲する。

**監視対象**: co-autopilot（主）, co-issue, co-architect, co-project, co-utility

**起動場所**: bare repo の main ディレクトリ（ADR-014 Decision 2）

## Step 0: モード判定

ユーザー入力からモードを判定する。

| モード | 判定条件 | 動作 |
|---|---|---|
| supervise | supervise / 監視 / watch / autopilot 起動 / session 名指定 | Step 1 へ |
| delegate-test | test / テスト / scenario / シナリオ / 壁打ち | Step 2 へ |
| retrospect | retrospect / 振り返り / 集約 / 過去の介入 | Step 3 へ |

引数なし or 曖昧な場合は AskUserQuestion で 3 モードから選択させる。

## Step 1: supervise モード — controller session 監視

1. `tmux list-windows` で観察可能 window 一覧を取得し、**自 window を除外**してユーザーに提示
2. 複数候補がある場合は AskUserQuestion で監視対象を選択
3. `commands/observe-once.md` を Read → 実行（対象 session のスナップショット取得）
4. `commands/problem-detect.md` を Read → 実行（Agent(observer-evaluator) で問題分類）
5. 問題が検出された場合: `refs/intervention-catalog.md` を Read → 層に応じた介入コマンド実行:
   - Layer 0 Auto → `commands/intervene-auto.md`
   - Layer 1 Confirm → `commands/intervene-confirm.md`
   - Layer 2 Escalate → `commands/intervene-escalate.md`
6. 継続監視するか AskUserQuestion で確認 → 継続なら Step 1-3 に戻る

## Step 2: delegate-test モード — co-self-improve へのテスト委譲

テストシナリオの設計・実行・管理は co-self-improve の専門領域。

1. ユーザーの要求（シナリオ名 / テスト種別 / smoke/regression）を確認
2. `Skill(twl:co-self-improve)` を scenario-run モードで呼び出し、要求をそのまま渡す
3. co-self-improve の完了を待ち、結果をユーザーに提示

## Step 3: retrospect モード — 過去の介入記録集約

1. `mcp__doobidoo__memory_search` で過去の介入結果を検索
   （キーワード: observation, intervention, detect, observer）
2. `refs/observation-pattern-catalog.md` を Read → パターンと照合
3. 集約結果をユーザーに提示
4. 新たな Issue 化が必要か AskUserQuestion で確認
5. 承認時のみ Issue draft 生成（`commands/issue-draft-from-observation.md`）

## Step 4: Wave 管理 — co-autopilot spawn + 結果収集

1. Issue 群の Wave 分割を計画（または既存の Wave 計画を継続）
   - `.autopilot/plan.yaml` の phases を確認し、未完了の Wave を特定する
2. Wave N の Issue リストを確定し、ユーザーに提示して承認を得る
3. `Skill(twl:session:spawn)` で co-autopilot を起動:
   ```
   /session:spawn co-autopilot --issues <issue_list> --wave <N>
   ```
4. observe ループを開始（Step 5 の observe を定期実行）
   - co-autopilot の進捗を監視し、問題を検知したら介入する
5. Wave 完了を検知したら結果を収集:
   - `commands/wave-collect.md` を Read → 実行（`WAVE_NUM=<N>` を環境変数で渡す）
6. 状態を外部化:
   - `commands/externalize-state.md` を Read → 実行（`--trigger wave_complete`）
7. SU-6 制約: `Skill(twl:su-compact)` を呼び出して知識外部化 + compaction を実行する
8. 次 Wave の Issue がある場合は Step 4-2 に戻る。全 Wave 完了時はサマリをユーザーに報告して Step 1 へ戻る

## Step 5: Long-term Memory 保存（後続 Issue で詳細化）

> **NOTE**: このステップは後続 Issue で詳細実装される。基本構造のみ定義。

ADR-014 Decision 3 の三層記憶モデルに基づく Memory MCP への永続化を担う。

## Step 6: Compaction 知識外部化 — su-compact コマンドへの委譲

`Skill(twl:su-compact)` を呼び出して知識外部化 + compaction を実行する。

### 呼出パターン

| ユーザー指示 | 実行モード | 動作 |
|---|---|---|
| `compact` / 外部化 / 記憶固定 / 整理 | 自動判定 | 状況に応じた外部化 + compaction |
| `compact --wave` | wave | Wave 完了サマリ外部化 + compaction |
| `compact --task` | task | タスク状態保存 + compaction |
| `compact --full` | full | 全知識の外部化 + compaction |

### SU-5 制約: context 50% 閾値自動監視

su-observer は定期的に（または Stop hook で）context 消費量を確認する。
context 消費量が 50% に到達した時点で、自動的に Step 6 の実行を提案しなければならない（SHALL）。

### SU-6 制約: Wave 完了時の自動 compaction

Wave 完了を検知した後（Step 4 の wave-collect 実行後）、su-compact を実行しなければならない（SHALL）。
次 Wave の開始前に必ず本ステップを完了すること。

## Step 7: セッション終了

1. 進行中の監視ループを停止
2. 未処理の介入記録を集約・保存
3. 終了をユーザーに通知

## 禁止事項（MUST NOT）

- Issue の直接実装をしてはならない（制約 OBS-3）
- 検出結果をユーザー確認なしで自動 Issue 起票してはならない（制約 OB-4）
- テストシナリオの実行を自身で行ってはならない（co-self-improve に委譲すること）
- context 消費量が 50% を超過した状態で compact モードへの誘導なしに処理を継続してはならない（SU-5）
- Wave 完了後に su-compact を省略して次 Wave を開始してはならない（SU-6）
