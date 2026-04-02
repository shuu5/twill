---
name: dev:co-autopilot
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
| `"lpd#42 loom#50"` | issues | クロスリポジトリ Issue リスト |
| `--board` | board | Board の非 Done Issue を自動取得 |
| `--auto` | （MODEに付加） | AUTO=true |
| `--repos '{"lpd":{...}}'` | （REPOSに設定） | クロスリポジトリ設定 JSON |

PROJECT_DIR を取得し、REPO_MODE を自動判定、AUTOPILOT_DIR を export:
```bash
PROJECT_DIR=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")
if [ -d "${PROJECT_DIR}/.bare" ]; then
  REPO_MODE="worktree"
else
  REPO_MODE="standard"
fi
export AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"
```

### クロスリポジトリ引数解析

`--repos` が指定された場合、JSON 文字列から repos 情報を解析:
```bash
# --repos '{"lpd":{"owner":"shuu5","name":"loom-plugin-dev","path":"..."},"loom":{"owner":"shuu5","name":"loom","path":"..."}}'
REPOS_ARG=""
if [ -n "${REPOS_JSON:-}" ]; then
  REPOS_ARG="--repos '$REPOS_JSON'"
fi
```

## Step 1: plan.yaml 生成

```bash
# --explicit / --issues モード
bash $SCRIPTS_ROOT/autopilot-plan.sh \
  --explicit|--issues "<input>" \
  --project-dir "$PROJECT_DIR" \
  --repo-mode "$REPO_MODE" \
  $REPOS_ARG

# --board モード（Board の非 Done Issue を自動取得）
bash $SCRIPTS_ROOT/autopilot-plan.sh \
  --board \
  --project-dir "$PROJECT_DIR" \
  --repo-mode "$REPO_MODE"
```

plan.yaml は Phase 配列（依存順）を定義。循環依存検出時はエラー終了（不変条件 I）。

## Step 2: 計画承認

AUTO 時 → 自動承認。通常時 → AskUserQuestion で Phase 構成を表示し確認。

TaskCreate で全体タスク「Autopilot: N Phases, M Issues」を登録。

## Step 3: セッション初期化

`commands/autopilot-init.md` を Read → 実行。

入力: PLAN_FILE。
出力: SESSION_ID, PHASE_COUNT, SESSION_STATE_FILE が設定される。

## Step 4: Phase ループ（orchestrator 委譲）

```
FOR P in 1..PHASE_COUNT:
  TaskCreate "Phase P: Issue #X, #Y" (status: in_progress)

  # autopilot-orchestrator.sh に Phase 実行を委譲
  REPORT=$(bash $SCRIPTS_ROOT/autopilot-orchestrator.sh \
    --plan "$PLAN_FILE" \
    --phase "$P" \
    --session "$SESSION_STATE_FILE" \
    --project-dir "$PROJECT_DIR" \
    --autopilot-dir "$AUTOPILOT_DIR" \
    $REPOS_ARG)

  # orchestrator が JSON レポート（PHASE_COMPLETE）を返す
  # Pilot は LLM 判断が必要な postprocess のみ実行
  → commands/autopilot-phase-postprocess.md を Read → 実行（retrospective / cross-issue のみ）

  TaskUpdate Phase P → completed
```

orchestrator が一括処理する内容:
- batch 分割・Worker 起動（autopilot-launch.sh）
- ポーリング（state-read.sh + crash-detect.sh、session-state.sh 対応）
- chain 遷移停止検知 + 自動 nudge（tmux capture-pane + send-keys）
- merge-gate 実行（merge-gate-execute.sh）
- window 管理（crash-detect → kill の原子的実行）
- Phase 完了レポート JSON 出力

Pilot LLM の責務は以下に限定:
- 計画承認（Step 2）
- retrospective 分析（postprocess 内）
- cross-issue 影響分析（postprocess 内）

### self-improve ECC 照合（autopilot-patterns 内）

autopilot-patterns が self-improve Issue 候補を検出した場合:
- 自リポジトリの Issue であれば ECC 照合を自動追加
- session.json の `self_improve_issues` フィールドに記録
- 別概念の controller には分離しない（ADR-002: controller-self-improve 吸収）

### 依存先 fail 時の skip 伝播（不変条件 D）

Phase N で fail した Issue に依存する Phase N+1 以降の全 Issue を自動 skip。
orchestrator 内で autopilot-should-skip.sh を呼び出し、自動的に skip + state 記録する。

## Step 5: 完了サマリー（orchestrator 委譲）

```bash
SUMMARY=$(bash $SCRIPTS_ROOT/autopilot-orchestrator.sh \
  --summary \
  --session "$SESSION_STATE_FILE" \
  --autopilot-dir "$AUTOPILOT_DIR")
```

orchestrator が全 issue-{N}.json を集約し、done/failed/skipped の件数と詳細を JSON で出力。
Pilot は JSON をパースしてユーザーに結果を報告する。

TaskUpdate 全体タスク → completed。

## 再開機能

issue-{N}.json の status から自動判定:
- `done` → skip
- `failed` → 依存先 skip（不変条件 D）
- `merge-ready` → 即 merge-gate 実行
- `running` → crash-detect.sh でクラッシュ検知（不変条件 G）。session-state.sh 利用可能時は 5 状態検出（idle/input-waiting/processing/error/exited）、非存在時は tmux list-panes フォールバック

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

co-autopilot 自体の障害時のみ手動パスを許可。bypass 使用時は retrospective で理由を記録。

### orchestrator 障害時の手動パス

autopilot-orchestrator.sh に障害がある場合、以下の手動パスで Phase 実行可能:
1. `commands/autopilot-phase-execute.md` を Read → 手動実行（従来方式）
2. `commands/autopilot-poll.md` を Read → 手動ポーリング
3. `commands/autopilot-summary.md` を Read → 手動サマリー

## 禁止事項（MUST NOT）

- plan.yaml を独自生成してはならない（autopilot-plan.sh に委譲）
- --auto 未指定時に計画確認をスキップしてはならない
- Worker が worktree を削除してはならない（不変条件 B）
- merge-gate 失敗時に rebase を試みてはならない（不変条件 F）
- trivial change であっても co-autopilot を bypass してはならない（Emergency Bypass 条件を除く）
