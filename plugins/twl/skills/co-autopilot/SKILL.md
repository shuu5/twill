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
- Agent(worker-*, e2e-*, autofix-loop, ac-scaffold-tests)
- session:spawn
spawnable_by:
- user
- su-observer
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

`PROJECT_DIR`・`REPO_MODE`・`AUTOPILOT_DIR` を自動判定し export する。

## Step 1: plan.yaml 生成

`autopilot-plan.sh` に `--explicit|--issues "<input>"` または `--board` を渡して plan.yaml を生成する（循環依存 → エラー終了、不変条件 I）。

**MUST:** `--issues` はスペース区切り（カンマ禁止）。`--project-dir` または `--repo-mode` は必須。

## Step 2: 計画承認

AUTO 時 → 自動承認。通常時 → AskUserQuestion で Phase 構成を表示し確認。

TaskCreate で全体タスク「Autopilot: N Phases, M Issues」を登録。

## Step 3: セッション初期化

`refs/co-autopilot-session-init.md` を Read → PYTHONPATH 設定・audit 開始・AUTOPILOT_DIR 一致確認を実行。

`commands/autopilot-init.md` を Read → 実行。出力: SESSION_ID, PHASE_COUNT, SESSION_STATE_FILE。

## Step 3.5: su-observer からの監視受入

`refs/co-autopilot-su-observer-integration.md` を Read → 参照。

Worker auto mode 確認方針は `refs/co-autopilot-worker-auto-mode.md` を Read → 参照。

## Step 4: Phase ループ（orchestrator 委譲）

`commands/autopilot-pilot-wakeup-loop.md` を Read → 実行（orchestrator 起動・PHASE_COMPLETE 検知・stagnation 検知・Silence heartbeat を atomic に委譲）。PHASE_COMPLETE 受信後 Step 4.5 へ進む。

### Step 4.5: Phase 完了サニティチェック（MUST）

`refs/co-autopilot-phase-sanity.md` を Read → 実行。

## Step 5: 完了サマリー（orchestrator 委譲）

`autopilot-orchestrator.sh --summary --session --autopilot-dir` で issue-{N}.json を集約し done/failed/skipped を報告する。TaskUpdate 全体タスク → completed。

`refs/co-autopilot-session-init.md` を Read → クリーンアップ・audit off を実行。

## 再開機能

issue-{N}.json の status から自動判定:
- `done` → skip
- `failed` → 依存先 skip（不変条件 D）
- `merge-ready` → 即 merge-gate 実行
- `running` → crash-detect.sh でクラッシュ検知（不変条件 G）

## state file 解決ルール

→ [`architecture/domain/contexts/autopilot.md` — State Management セクション](../architecture/domain/contexts/autopilot.md#state-management) を参照。

## 不変条件

→ [`architecture/domain/contexts/autopilot.md` — Constraints セクション](../architecture/domain/contexts/autopilot.md#constraints) を参照（不変条件 A〜M の正典）。本文中の ID 参照が各 Step の制約根拠。

## chain 停止時の復旧手順

→ [`architecture/domain/contexts/autopilot.md` — Recovery Procedures セクション](../architecture/domain/contexts/autopilot.md#recovery-procedures) を参照（不変条件 M）。

## Emergency Bypass

障害時のみ手動パスを許可（retrospective 必須）。`commands/autopilot-phase-execute.md`・`commands/autopilot-poll.md`・`commands/autopilot-summary.md` を Read → 手動実行。

マージ手順は `refs/co-autopilot-emergency-bypass.md` を Read → 実行。

## 禁止事項（MUST NOT）

- plan.yaml を独自生成してはならない（制約 AP-1）
- --auto 未指定時に計画確認をスキップしてはならない（UX ルール）
- Worker が worktree を削除してはならない（不変条件 B）
- merge-gate 失敗時に rebase を試みてはならない（不変条件 F）
- trivial change であっても co-autopilot を bypass してはならない（制約 AP-2）
- Pilot は Worker の代わりに Issue を直接実装してはならない（不変条件 K）。Worker 失敗時は根本原因分析 → Issue 化で対処する
- **Worker chain 停止時に Pilot が直接 nudge してマージしてはならない（不変条件 M）**。chain 停止時の復旧手順に従い orchestrator 再起動 or 手動 workflow inject で再開すること。specialist review スキップ禁止
