---
name: twl:co-observer
description: |
  Observer メタ認知コントローラー（ADR-013）。
  autopilot セッションを監視し、3 層介入プロトコル（Auto/Confirm/Escalate）に従って
  問題を検出・分類・対処する。co-self-improve へのテスト委譲も担う。

  Use when user: says co-observer/observer/介入/intervention/監視,
  wants to monitor a running autopilot session,
  wants to intervene in a Worker's state,
  wants to delegate test scenario execution to co-self-improve.
type: observer
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
---

# co-observer

メタ認知レイヤー。全 controller セッションを監視し、問題を検出したとき
`refs/intervention-catalog.md` の 3 層分類（Auto/Confirm/Escalate）に基づいて介入する。
テストシナリオ実行は co-self-improve に委譲する。

**監視対象**: co-autopilot（主）, co-issue, co-architect, co-project, co-utility

## Step 0: モード判定

ユーザー入力からモードを判定する。

| モード | キーワード | 動作 |
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

## 禁止事項（MUST NOT）

- Issue の直接実装をしてはならない（制約 OBS-3）
- observed session に inject / send-keys してはならない（制約 OB-3）
- 検出結果をユーザー確認なしで自動 Issue 起票してはならない（制約 OB-4）
- テストシナリオの実行を自身で行ってはならない（co-self-improve に委譲すること）
