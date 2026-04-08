---
name: twl:co-self-improve
description: |
  ライブセッション観察と能動的 self-improvement framework。
  別 session (autopilot/co-issue/co-architect) を read-only 観察し、
  問題検出 → Issue draft → ユーザー確認 → 起票までを統括する。
  テストプロジェクト (隔離 worktree) 上での負荷シナリオ壁打ちも管理する。

  Use when user: says co-self-improve/observation/観察/壁打ち/テストプロジェクト/load test,
  wants to observe a running session,
  wants to retrospect past observations.
type: controller
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
---

# co-self-improve

ライブセッション観察と能動的 self-improvement framework。

## Step 0: モード判定

ユーザー入力（引数 or プロンプト）からモードを判定する。

| モード | キーワード | 動作 |
|---|---|---|
| observe | observe / 観察 / 監視 / window 名指定 | Step 1a → Step 2 |
| scenario-run | scenario / シナリオ / 壁打ち / smoke / regression | Step 1b → Step 2 |
| retrospect | retrospect / 振り返り / 集約 / pattern | Step 3 |
| test-project-manage | init / reset / status / clean / cleanup | Step 4 |

引数なし or 曖昧な場合は AskUserQuestion で 4 モードから選択させる。

## Step 1a: observe モード — 対象 session 選択

`tmux list-windows` で観察可能 window 一覧を取得し、**自 window を除外**してユーザーに提示。
複数候補がある場合は AskUserQuestion で選択。

## Step 1b: scenario-run モード — シナリオ選択 + spawn

1. `commands/test-project-init.md` を Read → 実行（test-target worktree が無ければ作成）
2. `refs/test-scenario-catalog.md` を Read してシナリオ一覧表示
3. ユーザーがシナリオ選択
4. `commands/test-project-scenario-load.md` を Read → 実行（シナリオの Issue 群を test-target にロード）
5. `Skill(session:spawn)` で `--cd worktrees/test-target` を指定し observed session を起動
6. spawn 後の window 名を取得し Step 2 へ

## Step 2: observation loop 起動

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

- observed session に inject / send-keys してはならない（read-only 観察）
- 検出結果を**ユーザー確認なしで**自動 Issue 起票してはならない
- テストプロジェクト worktree から実 main branch にコミットしてはならない
- 同時に 4 個以上の observed session を観察してはならない（context budget 維持）
