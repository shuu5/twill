---
name: twl:co-self-improve
description: |
  テストシナリオ実行と self-improvement arm。
  co-observer から委譲されるテスト実行モード（scenario-run）と、
  テストプロジェクト管理、過去観察の retrospect を担う。
  直接セッション監視は co-observer に移管済み（observe モード: deprecated）。

  Use when user: says co-self-improve/壁打ち/テストプロジェクト/load test/scenario,
  wants to run test scenarios on test-target worktree,
  wants to manage the test project,
  wants to retrospect past observations.
  Observation/監視 → co-observer を使うこと。
type: controller
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
- co-observer
---

# co-self-improve

テストシナリオ実行 arm。scenario-run / retrospect / test-project-manage の 3 モードに特化する。

**位置づけ**: co-observer（上位）から委譲されるテスト実行モードとして機能する。
セッション監視・介入は co-observer が担い、co-self-improve はシナリオ実行と知識蓄積に集中する。

## Step 0: モード判定

ユーザー入力（引数 or プロンプト）からモードを判定する。

| モード | キーワード | 動作 |
|---|---|---|
| scenario-run | scenario / シナリオ / 壁打ち / smoke / regression | Step 1b → Step 2 |
| retrospect | retrospect / 振り返り / 集約 / pattern | Step 3 |
| test-project-manage | init / reset / status / clean / cleanup | Step 4 |

> **注意**: `observe / 観察 / 監視` キーワードは **deprecated**。
> セッション監視は co-observer の supervise モードを使用してください。

引数なし or 曖昧な場合は AskUserQuestion で 3 モードから選択させる。

## [DEPRECATED] observe モード

このモードは co-observer の supervise モードに移管されました。
`observe / 観察 / 監視` のキーワードが入力された場合は、
AskUserQuestion で co-observer への誘導を行う。

## Step 1: scenario-run モード — シナリオ選択 + spawn

1. `commands/test-project-init.md` を Read → 実行（test-target worktree が無ければ作成）
2. `refs/test-scenario-catalog.md` を Read してシナリオ一覧表示
3. ユーザーがシナリオ選択
4. `commands/test-project-scenario-load.md` を Read → 実行（シナリオの Issue 群を test-target にロード）
5. `Skill(session:spawn)` で `--cd worktrees/test-target` を指定し observed session を起動
6. spawn 後の window 名を取得し Step 2 へ

## Step 2: scenario 実行中の observation loop 起動

`Skill(twl:workflow-observe-loop)` を呼び出し、対象 window を引数で渡す。
workflow が完了（検出 0 件 or ユーザー停止 or タイムアウト）するまで委譲。

## Step 3: retrospect モード

1. `mcp__doobidoo__memory_search` で過去の observation 結果を検索（キーワード: observation, detection, pattern）
2. `commands/observe-retrospective.md` を Read → 実行
3. 集約結果をユーザーに提示し、Issue draft 生成有無を AskUserQuestion で確認
4. 承認時は `commands/issue-draft-from-observation.md` 経由で Issue draft 生成

## Step 4: test-project-manage モード

ユーザー指示に基づき以下のいずれかを呼ぶ:

- `commands/test-project-init.md`（新規作成）
- `commands/test-project-reset.md`（clean state へ戻す）
- `commands/test-project-scenario-load.md`（シナリオ投入）
- 状態確認は `git -C worktrees/test-target status` を直接実行

## Step 5: Issue 起票確認（Step 2 / Step 3 経由）

検出された問題があれば、以下の MUST フローを踏む:

1. 検出結果を全件提示（severity / category / source / capture excerpt）
2. AskUserQuestion で「Issue draft 生成しますか?」（全件 / 一部 / なし）
3. 承認時のみ `commands/issue-draft-from-observation.md` を呼ぶ
4. draft をユーザーに見せて最終確認（MUST）
5. 承認時のみ `gh issue create` で起票（label: `from-observation`, `ctx/observation` 必須）

## 禁止事項（MUST NOT）

- observed session に inject / send-keys してはならない（制約 OB-3）
- 検出結果をユーザー確認なしで自動 Issue 起票してはならない（制約 OB-4）
- テストプロジェクト worktree から実 main branch にコミットしてはならない（制約 SI-1）
- 同時に 3 observed session を超えて観察してはならない（制約 OB-5）

Live Observation 制約の正典は `plugins/twl/architecture/domain/contexts/observation.md`
Self-Improve 制約の正典は `plugins/twl/architecture/domain/contexts/self-improve.md`
