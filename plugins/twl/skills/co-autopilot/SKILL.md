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

`autopilot-orchestrator.sh --plan --phase --session --project-dir --autopilot-dir [$REPOS_ARG]` で Phase 実行を委譲。orchestrator は JSON レポート（PHASE_COMPLETE）を返す。実装詳細（batch 分割・Worker 起動・ポーリング・merge-gate・skip 伝播 [不変条件 D]）は orchestrator が正典。Pilot LLM の責務は計画承認・retrospective・cross-issue 分析に限定。
<!-- NOTE: Pilot 用 atomic (autopilot-pilot-precheck, autopilot-pilot-rebase, autopilot-multi-source-verdict) 経由であれば、PR diff stat / AC spot-check 等の能動評価は許容される。設計原則 P1 (ADR-010) 参照。 -->

### Step 4.5: Phase 完了サニティチェック（MUST）

PHASE_COMPLETE 受信後、以下の順序で実行する（各 atomic の処理詳細は各 .md を正典とする）:

1. `commands/autopilot-phase-sanity.md` を Read → 実行（Issue close 状態 verify）
2. `commands/autopilot-pilot-precheck.md` を Read → 実行（PR diff stat 削除確認 + AC spot-check）
3. precheck が WARN (high-deletion) を出した場合 → `commands/autopilot-pilot-rebase.md` を Read → 実行（Pilot 介入 rebase）
4. precheck / rebase の結果から再 verify が必要な場合 → `commands/autopilot-multi-source-verdict.md` を Read → 実行（multi-source 統合判断）
5. `commands/autopilot-phase-postprocess.md` を Read → 実行（retrospective / cross-issue / self-improve ECC 照合）

`PILOT_ACTIVE_REVIEW_DISABLE=1` の場合、手順 2-4 はスキップされる（各 atomic 内で opt-out 処理）。

TaskUpdate Phase P → completed。

## Step 5: 完了サマリー（orchestrator 委譲）

`autopilot-orchestrator.sh --summary --session --autopilot-dir` で全 issue-{N}.json を集約し、done/failed/skipped の件数と詳細を JSON で出力。Pilot はパースしてユーザーに報告する。TaskUpdate 全体タスク → completed。

サマリー報告後、一括クリーンアップを実行:
```bash
bash "$SCRIPTS_ROOT/autopilot-cleanup.sh" --autopilot-dir "$AUTOPILOT_DIR"
```
done state file を即座にアーカイブし、TTL 超過の failed state file もアーカイブ。孤立 worktree を検出・削除する。`--dry-run` で事前確認も可能。

## 再開機能

issue-{N}.json の status から自動判定:
- `done` → skip
- `failed` → 依存先 skip（不変条件 D）
- `merge-ready` → 即 merge-gate 実行
- `running` → crash-detect.sh でクラッシュ検知（不変条件 G）

## 不変条件

不変条件 A〜I の正典は `architecture/autopilot-invariants.md`（A=状態一意, B=Worktree 削除 Pilot 専任, C=Worker マージ禁止, D=fail skip 伝播, E=merge-gate リトライ最大1, F=merge 失敗時 rebase 禁止, G=クラッシュ検知, H=deps.yaml 変更排他, I=循環依存拒否）。本文中の ID 参照のみが各 Step の制約根拠。

## Emergency Bypass

co-autopilot 自体の障害時のみ手動パスを許可。bypass 使用時は retrospective で理由を記録。障害時は `commands/autopilot-phase-execute.md`・`commands/autopilot-poll.md`・`commands/autopilot-summary.md` を Read → 手動実行。

### Emergency Bypass 時のマージ手順（MUST NOT 直接 gh pr merge）

Worker の `non_terminal_chain_end` 等で orchestrator が Emergency Bypass としてマージを実行する場合、**`gh pr merge` を直接呼んではならない**（squash ポリシーが適用されないため）。

必ず `mergegate merge --force` を使用すること:

```bash
python3 -m twl.autopilot.mergegate merge \
  --issue <ISSUE_NUM> \
  --pr <PR_NUMBER> \
  --branch <BRANCH> \
  --force
```

- `--force` がスキップするもの: `_check_running_guard()`（status=running 拒否）のみ
- `--force` でも維持されるもの: `_check_worktree_guard()`、`_check_worker_window_guard()`、`--squash` フラグ
- `gh pr merge --squash` が確実に呼ばれる（`--merge` ではない）

## 禁止事項（MUST NOT）

- plan.yaml を独自生成してはならない（autopilot-plan.sh に委譲）
- --auto 未指定時に計画確認をスキップしてはならない
- Worker が worktree を削除してはならない（不変条件 B）
- merge-gate 失敗時に rebase を試みてはならない（不変条件 F）
- trivial change であっても co-autopilot を bypass してはならない（Emergency Bypass 条件を除く）
