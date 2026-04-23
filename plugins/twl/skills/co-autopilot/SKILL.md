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
`PROJECT_DIR`（bare repo の親）と `REPO_MODE`（worktree/standard）を自動判定し `AUTOPILOT_DIR` を export する。`--repos` が指定された場合は JSON から repos 情報を解析し `REPOS_ARG` として保持する。

## Step 1: plan.yaml 生成

`autopilot-plan.sh` に `--explicit|--issues "<input>"` または `--board` を渡して plan.yaml を生成する。plan.yaml は Phase 配列（依存順）を定義。循環依存検出時はエラー終了（不変条件 I）。

**引数フォーマット（MUST）:**
- `--issues` の値はスペース区切り。カンマ区切りは parse error になるため禁止
- `--project-dir` または `--repo-mode` のどちらかが必須

```bash
# 正しい呼び出し例（worktree モード）
bash autopilot-plan.sh --issues "84 78 83" --project-dir "$PROJECT_DIR"

# repo-mode の場合
bash autopilot-plan.sh --issues "84 78" --repo-mode standard --project-dir "$PROJECT_DIR"
```

## Step 2: 計画承認

AUTO 時 → 自動承認。通常時 → AskUserQuestion で Phase 構成を表示し確認。

TaskCreate で全体タスク「Autopilot: N Phases, M Issues」を登録。

## Step 3: セッション初期化

**事前準備（MUST）:** まず python-env.sh を source して PYTHONPATH を設定する:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/python-env.sh"
```

これにより `cli/twl/src` の絶対パスが `PYTHONPATH` に追加される（python-env.sh が BASH_SOURCE から絶対パスを自動解決）。省略すると `python3 -m twl.autopilot.*` 呼び出し時に `ModuleNotFoundError` が発生する。

**条件付き audit on（MUST）:** PYTHONPATH 設定後、audit が非アクティブな場合のみ audit を開始する（二重呼び出しによるセッション上書きを防止）:

```bash
if ! twl audit status 2>/dev/null | grep -q "^active: true"; then
  twl audit on
fi
```

`commands/autopilot-init.md` を Read → 実行。出力: SESSION_ID, PHASE_COUNT, SESSION_STATE_FILE。

**AUTOPILOT_DIR 一致確認（MUST）:** `autopilot-init` 実行前に、`AUTOPILOT_DIR` が `plan.yaml` と同じディレクトリを指していることを確認する。bare repo レイアウトでは `autopilot-plan.sh` が `.bare/` を検出して `main/.autopilot/` に plan.yaml を配置するため、Pilot も同じパスを使用すること。不一致はパストラバーサルエラーの原因になる (#660)。

## Step 3.5: su-observer からの監視受入

co-autopilot は su-observer から spawn・監視される設計になっている（ADR-014 Decision 2）。
su-observer が `supervise` モードで起動すると、co-autopilot の tmux window を監視対象として選択し
3 層介入プロトコル（Auto/Confirm/Escalate）に従って問題を検出・対処する。

**起動パターン:**

1. **co-autopilot 単独起動**（後方互換）: ユーザーが直接 `co-autopilot` を起動し、su-observer は別途起動して監視にアタッチする
2. **su-observer spawn 起動**: su-observer がユーザー指示に基づき co-autopilot セッションを spawn する（ADR-014 Decision 2 の正規フロー）

### spawn-controller.sh 経由 chain 連携起動（`--with-chain`）

su-observer が `spawn-controller.sh` 経由で co-autopilot を起動する場合、2 種類のモードを使い分ける:

| モード | コマンド例 | window 名 | state file | chain |
|--------|-----------|-----------|------------|-------|
| **standalone**（デフォルト） | `spawn-controller.sh co-autopilot /tmp/prompt.txt` | `wt-co-autopilot-<HHMMSS>` | 未生成 | 不回転 |
| **chain 連携**（`--with-chain`） | `spawn-controller.sh co-autopilot /tmp/ctx.txt --with-chain --issue N` | `ap-#N` | `issue-N.json` 生成 | 回転 |

chain 連携モード（`--with-chain`）では `spawn-controller.sh` が `autopilot-launch.sh` に委譲する。`autopilot-launch.sh` が state file 初期化・worktree 作成・orchestrator 起動・crash-detect hook 設定を担う。

```bash
# chain 連携起動例（su-observer からの典型的な呼び出し）
spawn-controller.sh co-autopilot /tmp/issue-835-ctx.txt --with-chain --issue 835

# --project-dir / --autopilot-dir は省略時に bare repo 構造から自動解決される
# 明示指定も可能:
spawn-controller.sh co-autopilot /tmp/ctx.txt --with-chain --issue 835 \
  --project-dir /path/to/project --autopilot-dir /path/to/.autopilot
```

co-autopilot は su-observer の存在を前提とせず動作する。su-observer との連携は state ファイル（`$AUTOPILOT_DIR/session.json`, `issue-{N}.json`）と tmux window 名を通じて疎結合に行われる。

### 起動経路比較（#836 文書化）

co-autopilot 起動には 2 経路が存在する。混同すると chain が不回転になる（`pitfalls-catalog §13` 参照）。

| 項目 | 経路 A: `autopilot-launch.sh`（Worker 起動） | 経路 B: `spawn-controller.sh co-autopilot`（Pilot spawn） |
|------|---------------------------------------------|----------------------------------------------------------|
| **呼び出し元** | co-autopilot Pilot（`autopilot-launch.md`） | su-observer |
| **window 名** | `ap-<N>`（Issue 番号ベース） | `wt-co-autopilot-<HHMMSS>` |
| **state file** | `issue-<N>.json` 生成（`--init`） | Pilot が内部で生成（経路 A を経由） |
| **起動対象** | Worker セッション（Issue 1 件） | Pilot セッション全体（co-autopilot SKILL） |
| **chain** | 回転（`/twl:workflow-setup #N` を inject） | co-autopilot Step 1-5 が回転 |
| **使用場面** | Issue 単位 Worker 起動（co-autopilot 内部） | observer から Issue 群を一括実装する場合 |
| **注意** | 直接呼び出し禁止（co-autopilot 内部専用） | state file は Pilot 経由（経路 A）で生成される |

### Worker auto mode 確認方針（observer 観察用 — Issue #800）

Pilot が `autopilot-launch.sh` で起動する Worker は `--permission-mode auto` 付きで cld 経由起動される。Worker pane tail に `⏵⏵ auto mode on` が出ない場合でも auto mode は有効である（positional prompt 即送信で status bar が上書きされる仕様。Issue #800 explore で全起動経路を検証済み）。observer / Pilot は以下の手順で間接的に確認する。

#### 確認方法 A（一次指標 — heartbeat / state file existence）

`autopilot-launch.sh` 起動後 5 秒以内に以下を実行し、Worker が正常起動したことを確認する:

```bash
# heartbeat ファイル または worker-*.json の存在を確認
ls .supervisor/events/heartbeat-* 2>/dev/null || ls .supervisor/events/worker-*.json 2>/dev/null
```

**期待出力**: 1 つ以上のファイル名が出力される（exit 0 + stdout に 1 行以上）。0 件かつ exit 非 0 の場合は Worker 起動失敗または delay。10 秒待って再試行する。

#### 確認方法 B（二次指標 — pane capture grep）

Worker が起動済み（pane が `Brewing` / `Concocting` / `idle` 等の LLM indicator を表示）状態で:

```bash
tmux capture-pane -t <worker-win> -p -S -50 | grep -E '⏵⏵ auto mode|permission_mode'
```

**期待出力**: 1 行以上のマッチ（exit 0）。マッチが見られれば auto mode 有効と判定。マッチが 0 行でも `autopilot-launch.sh` の起動行に `--permission-mode auto` が含まれる限り auto mode は有効（pane 上の表示有無は status bar 上書きタイミングに依存する）。

#### 注意事項

- pane tail に `⏵⏵ auto mode on` が出ないこと自体を「auto mode 効いていない」と誤認してはならない
- Worker bash で permission prompt（`1. Yes, proceed` / `2. No, and tell ...`）が出た場合、auto mode classifier の `soft_deny` 該当（仕様）の可能性が高い → su-observer の `refs/pitfalls-catalog.md` §4.7 / §4.8 で対処

## Step 4: Phase ループ（orchestrator 委譲）

`commands/autopilot-pilot-wakeup-loop.md` を Read → 実行（orchestrator 起動・PHASE_COMPLETE 検知・stagnation 検知・Silence heartbeat を atomic に委譲）。PHASE_COMPLETE 受信後 Step 4.5 へ進む。

### Step 4.5: Phase 完了サニティチェック（MUST）

PHASE_COMPLETE 受信後、以下を順次実行する:

1. `commands/autopilot-phase-sanity.md` を Read → 実行
2. `commands/autopilot-pilot-precheck.md` を Read → 実行（`PILOT_ACTIVE_REVIEW_DISABLE=1` 時はスキップ）
3. precheck が WARN (high-deletion) 時 → `commands/autopilot-pilot-rebase.md` を Read → 実行
4. 再 verify 必要時 → `commands/autopilot-multi-source-verdict.md` を Read → 実行
5. `commands/autopilot-phase-postprocess.md` を Read → 実行

TaskUpdate Phase P → completed。`python3 -m twl.autopilot.audit snapshot ...` で状態保全（audit 非アクティブ時は no-op）。

## Step 5: 完了サマリー（orchestrator 委譲）

`autopilot-orchestrator.sh --summary --session --autopilot-dir` で全 issue-{N}.json を集約し、done/failed/skipped の件数と詳細を JSON で出力。Pilot はパースしてユーザーに報告する。TaskUpdate 全体タスク → completed。

サマリー報告後、一括クリーンアップを実行:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-cleanup.sh" --autopilot-dir "$AUTOPILOT_DIR"
```
done state file を即座にアーカイブし、TTL 超過の failed state file もアーカイブ。孤立 worktree を検出・削除する。`--dry-run` で事前確認も可能。

**条件付き audit off（MUST）:** クリーンアップ後、audit がアクティブな場合のみ停止する（非 active 時の RuntimeError を防止）:

```bash
if twl audit status 2>/dev/null | grep -q "^active: true"; then
  twl audit off
fi
```

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

- plan.yaml を独自生成してはならない（制約 AP-1）
- --auto 未指定時に計画確認をスキップしてはならない（UX ルール）
- Worker が worktree を削除してはならない（不変条件 B）
- merge-gate 失敗時に rebase を試みてはならない（不変条件 F）
- trivial change であっても co-autopilot を bypass してはならない（制約 AP-2）
- Pilot は Worker の代わりに Issue を直接実装（`Agent(Implement Issue #N)` 等によるコード変更・PR 作成）してはならない（不変条件 K）。Worker 失敗時は根本原因分析 → Issue 化で対処する
- **Worker chain 停止時に Pilot が直接 nudge して PR 作成 → マージを実行してはならない（不変条件 M）**。chain 停止時は「chain 停止時の復旧手順」に従い orchestrator 再起動 or 手動 workflow inject で chain を再開すること。specialist review をスキップしたマージは禁止

Autopilot 制約の正典は `plugins/twl/architecture/domain/contexts/autopilot.md`
