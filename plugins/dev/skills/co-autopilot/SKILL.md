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
spawnable_by:
- user
---

# co-autopilot

Issue 実装の実行。Autopilot-first: 単一 Issue も本 controller 経由。

## Step 0: 引数解析

引数から MODE / AUTO / INPUT を判定。

| パターン | MODE | INPUT |
|---------|------|-------|
| `"#19, #18 → #20 → #23"` | explicit | 依存グラフ文字列 |
| `#18 #19 #20` | issues | Issue 番号リスト |
| `--auto` | （MODEに付加） | AUTO=true |

PROJECT_DIR を取得:
```bash
PROJECT_DIR=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")
```

## Step 1: plan.yaml 生成

```bash
bash $SCRIPTS_ROOT/autopilot-plan.sh \
  --explicit|--issues "<input>" \
  --project-dir "$PROJECT_DIR"
```

plan.yaml は Phase 配列（依存順）を定義。循環依存検出時はエラー終了（不変条件 I）。

## Step 2: 計画承認

AUTO 時 → 自動承認。通常時 → AskUserQuestion で Phase 構成を表示し確認。

TaskCreate で全体タスク「Autopilot: N Phases, M Issues」を登録。

## Step 3: セッション初期化

```bash
eval "$(bash $SCRIPTS_ROOT/autopilot-init.sh "$PLAN_FILE")"
```

SESSION_ID, PHASE_COUNT, SESSION_STATE_FILE が設定される。

## Step 4: Phase ループ

```
FOR P in 1..PHASE_COUNT:
  TaskCreate "Phase P: Issue #X, #Y" (status: in_progress)

  → autopilot-phase-execute を実行（Worker 起動 → ポーリング → merge-gate）
  → autopilot-phase-postprocess を実行（collect → retrospective → patterns → cross-issue）

  TaskUpdate Phase P → completed
```

### Phase 内の Worker 実行フロー

Worker は tmux window で起動され、chain ステップを逐次実行:
1. worktree 作成 → cd → 実装（setup chain → apply → pr-cycle chain）
2. 完了時: issue-{N}.json status を `merge-ready` に更新
3. Pilot が merge-gate 実行 → 成功で `done` に遷移

### self-improve ECC 照合（autopilot-patterns 内）

autopilot-patterns が self-improve Issue 候補を検出した場合:
- 自リポジトリの Issue であれば ECC 照合を自動追加
- session.json の `self_improve_issues` フィールドに記録
- 別概念の controller には分離しない（ADR-002: controller-self-improve 吸収）

### 依存先 fail 時の skip 伝播（不変条件 D）

Phase N で fail した Issue に依存する Phase N+1 以降の全 Issue を自動 skip。
skip された Issue の issue-{N}.json は `failed` + `{ message: "dependency failed" }` で記録。

## Step 5: 完了サマリー

autopilot-summary を実行。全 Phase 完了後に結果集計・レポート出力。

TaskUpdate 全体タスク → completed。

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

co-autopilot 自体の障害時のみ手動パスを許可。bypass 使用時は retrospective で理由を記録。

## 禁止事項（MUST NOT）

- plan.yaml を独自生成してはならない（autopilot-plan.sh に委譲）
- --auto 未指定時に計画確認をスキップしてはならない
- Worker が worktree を削除してはならない（不変条件 B）
- merge-gate 失敗時に rebase を試みてはならない（不変条件 F）
- trivial change であっても co-autopilot を bypass してはならない（Emergency Bypass 条件を除く）
