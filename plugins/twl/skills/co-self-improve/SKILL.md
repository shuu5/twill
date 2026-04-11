---
name: twl:co-self-improve
description: |
  テストシナリオ実行と self-improvement arm。
  su-observer から委譲されるテスト実行モード（scenario-run）と、
  テストプロジェクト管理、過去観察の retrospect を担う。
  直接セッション監視は su-observer に移管済み（observe モード: deprecated）。

  Use when user: says co-self-improve/壁打ち/テストプロジェクト/load test/scenario,
  wants to run test scenarios on test-target worktree,
  wants to manage the test project,
  wants to retrospect past observations.
  Observation/監視 → su-observer を使うこと。
type: controller
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
- su-observer
---

# co-self-improve

テストシナリオ実行 arm。scenario-run / retrospect / test-project-manage の 3 モードに特化する。

**位置づけ**: su-observer（上位）から `cld-spawn` で起動されるテスト実行コントローラー。
セッション監視・介入は su-observer が担い、co-self-improve はシナリオ実行と知識蓄積に集中する。

## su-observer からの spawn 受取手順

su-observer が `cld-spawn` で本スキルを起動する際、spawn 時プロンプトに以下の情報が含まれる。
起動後に必ずプロンプトを確認し、以降の動作に反映すること。

| 項目 | 説明 | 例 |
|------|------|----|
| 対象 session | 観察対象の tmux window 名 | `worktrees/test-target` |
| タスク内容 | 実行するシナリオ名または指示 | `scenario: smoke-test-issue-123` |
| 観察モード | single / loop | `observe: single` |

プロンプトに情報が含まれている場合は AskUserQuestion でモード確認をスキップし、直接 Step 1 / 3 / 4 に進む。
情報が不完全な場合のみ AskUserQuestion で補完する。

## Step 0: モード判定

ユーザー入力（引数 or プロンプト）からモードを判定する。

| モード | キーワード | 動作 |
|---|---|---|
| scenario-run | scenario / シナリオ / 壁打ち / smoke / regression | Step 1b → Step 2 |
| retrospect | retrospect / 振り返り / 集約 / pattern | Step 3 |
| test-project-manage | init / reset / status / clean / cleanup | Step 4 |

> **注意**: `observe / 観察 / 監視` キーワードは **deprecated**。
> セッション監視は su-observer を使用してください。

spawn 時プロンプトに情報が含まれない場合のみ AskUserQuestion で 3 モードから選択させる。

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
