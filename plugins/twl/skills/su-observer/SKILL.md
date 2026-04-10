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

## Step 4: Wave 管理（後続 Issue で詳細化）

> **NOTE**: このステップは後続 Issue で詳細実装される。基本構造のみ定義。

Wave 単位の co-autopilot 起動・完了検知・結果集約を担う。

## Step 5: Long-term Memory 保存（後続 Issue で詳細化）

> **NOTE**: このステップは後続 Issue で詳細実装される。基本構造のみ定義。

ADR-014 Decision 3 の三層記憶モデルに基づく Memory MCP への永続化を担う。

## Step 6: Compaction 知識外部化（後続 Issue で詳細化）

> **NOTE**: このステップは後続 Issue で詳細実装される。基本構造のみ定義。

ADR-014 Decision 4 の PreCompact/PostCompact/SessionStart(compact) hook 連携を担う。

## Step 7: セッション終了

1. 進行中の監視ループを停止
2. 未処理の介入記録を集約・保存
3. 終了をユーザーに通知

## 禁止事項（MUST NOT）

- Issue の直接実装をしてはならない（制約 OBS-3）
- 検出結果をユーザー確認なしで自動 Issue 起票してはならない（制約 OB-4）
- テストシナリオの実行を自身で行ってはならない（co-self-improve に委譲すること）
