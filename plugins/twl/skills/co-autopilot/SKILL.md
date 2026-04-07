---
name: twl:co-autopilot
description: |
  依存グラフに基づくIssue群一括自律実装オーケストレーター。
  Pilot セッションが tmux window 作成・cld 起動・Phase 管理・merge-gate を統括。
  単一 Issue も co-autopilot 経由（Autopilot-first 原則）。

  Use when user: says autopilot/オートパイロット/一括実装/全Issue実装,
  says 実装して/implement,
  wants to run issues automatically.
type: controller
effort: high
tools:
- Agent(worker-*, e2e-*, autofix-loop, spec-scaffold-tests)
spawnable_by:
- user
---

# co-autopilot

Issue 実装の実行。Autopilot-first: 単一 Issue も本 controller 経由。

## Step 0: 引数解析

引数から MODE / AUTO / INPUT / REPOS を判定。

| パターン | MODE | INPUT |
|---------|------|-------|
| `"#19, #18 → #20 → #23"` | explicit | 依存グラフ文字列 |
| `#18 #19 #20` | issues | Issue 番号リスト |
| `"lpd#42 twill#50"` | issues | クロスリポジトリ Issue リスト |
| `--board` | board | Board の非 Done Issue を自動取得 |
| `--auto` | （MODEに付加） | AUTO=true |
| `--repos '{"lpd":{...}}'` | （REPOSに設定） | クロスリポジトリ設定 JSON |

`PROJECT_DIR`（bare repo の親）と `REPO_MODE`（worktree/standard）を自動判定し `AUTOPILOT_DIR` を export する。`--repos` が指定された場合は JSON から repos 情報を解析し `REPOS_ARG` として保持する。

## Step 1: plan.yaml 生成

`autopilot-plan.sh` に `--explicit|--issues "<input>"` または `--board` を渡して plan.yaml を生成する。plan.yaml は Phase 配列（依存順）を定義。循環依存検出時はエラー終了（不変条件 I）。

## Step 2: 計画承認

AUTO 時 → 自動承認。通常時 → AskUserQuestion で Phase 構成を表示し確認。

TaskCreate で全体タスク「Autopilot: N Phases, M Issues」を登録。

## Step 3: セッション初期化

`commands/autopilot-init.md` を Read → 実行。出力: SESSION_ID, PHASE_COUNT, SESSION_STATE_FILE。

## Step 4: Phase ループ（orchestrator 委譲）

`autopilot-orchestrator.sh --plan --phase --session --project-dir --autopilot-dir [$REPOS_ARG]` で Phase 実行を委譲。orchestrator は JSON レポート（PHASE_COMPLETE）を返す。

### Step 4.5: Phase 完了サニティチェック（MUST）

PHASE_COMPLETE 受信後、`commands/autopilot-phase-sanity.md` を Read → 実行する。
**処理ロジックの詳細は autopilot-phase-sanity.md を正典とする**（SKILL.md 側では責務範囲のみ記述）。

役割: 各 done Issue の GitHub Issue close 状態を verify し、必要に応じて修正後の results JSON（auto_close_fallback / sanity_warnings 付き）を返す。Pilot LLM は PR diff・Issue body を読まず、Issue state のみを参照する（context budget 維持）。

Pilot は次に `commands/autopilot-phase-postprocess.md` を Read → 実行（retrospective / cross-issue のみ）。TaskUpdate Phase P → completed。

orchestrator が一括処理する内容:
- batch 分割・Worker 起動・ポーリング・chain 遷移停止検知 + 自動 nudge
- merge-gate 実行・window 管理・Phase 完了レポート JSON 出力

Pilot LLM の責務は計画承認・retrospective 分析・cross-issue 影響分析に限定する。

### self-improve ECC 照合

autopilot-patterns が self-improve Issue 候補を検出した場合、自リポジトリの Issue であれば ECC 照合を自動追加し `session.json` の `self_improve_issues` に記録する。

### 依存先 fail 時の skip 伝播（不変条件 D）

Phase N で fail した Issue に依存する後続 Issue を自動 skip する（orchestrator 内で autopilot-should-skip.sh を実行）。

## Step 5: 完了サマリー（orchestrator 委譲）

`autopilot-orchestrator.sh --summary --session --autopilot-dir` で全 issue-{N}.json を集約し、done/failed/skipped の件数と詳細を JSON で出力。Pilot はパースしてユーザーに報告する。TaskUpdate 全体タスク → completed。

## 再開機能

issue-{N}.json の status から自動判定:
- `done` → skip
- `failed` → 依存先 skip（不変条件 D）
- `merge-ready` → 即 merge-gate 実行
- `running` → crash-detect.sh でクラッシュ検知（不変条件 G）

## 不変条件（9件）

| ID | 概要 |
|----|------|
| A | 状態の一意性（running/merge-ready/done/failed） |
| B | Worktree 削除 Pilot 専任 |
| C | Worker マージ禁止（merge-ready 宣言のみ） |
| D | 依存先 fail 時の skip 伝播 |
| E | merge-gate リトライ制限（最大1回） |
| F | merge 失敗時 rebase 禁止 |
| G | クラッシュ検知保証 |
| H | deps.yaml 変更排他性（separate Phase） |
| I | 循環依存拒否 |

## Emergency Bypass

co-autopilot 自体の障害時のみ手動パスを許可。bypass 使用時は retrospective で理由を記録。障害時は `commands/autopilot-phase-execute.md`・`commands/autopilot-poll.md`・`commands/autopilot-summary.md` を Read → 手動実行。

## 禁止事項（MUST NOT）

- plan.yaml を独自生成してはならない（autopilot-plan.sh に委譲）
- --auto 未指定時に計画確認をスキップしてはならない
- Worker が worktree を削除してはならない（不変条件 B）
- merge-gate 失敗時に rebase を試みてはならない（不変条件 F）
- trivial change であっても co-autopilot を bypass してはならない（Emergency Bypass 条件を除く）
