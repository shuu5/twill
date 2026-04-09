---
name: twl:workflow-issue-create
description: |
  Issue 一括作成ワークフロー（co-issue Phase 4 を分離）。
  refined ラベル事前作成 → ユーザー確認 → creation routing → Project Board 同期 → クリーンアップ。

  Use when user: says Issue作成/issue-create,
  or when called from co-issue workflow.
type: workflow
effort: medium
spawnable_by:
- controller
can_spawn:
- atomic
- script
---

# workflow-issue-create

co-issue Phase 4（一括作成）を独立させたワークフロー。

## 入力インターフェース

LLM コンテキスト内フラグとして受け渡し:

- **refined_issues**: 精緻化済み Issue リスト
- **REFINED_LABEL_OK**: refined ラベル作成成否フラグ
- **is_split_generated**: 各 Issue の split 由来フラグ
- **is_quick_candidate**: 各 Issue の quick 候補フラグ
- **cross_repo_split**: クロスリポ分割フラグ
- **target_repos**: クロスリポ対象リポジトリリスト

## 出力インターフェース

- **created_issue_urls**: 作成された Issue の URL リスト

## 処理フロー

### Step 1: refined ラベル事前作成

`gh label create refined --description "Refined by co-issue" --color "0E8A16" 2>/dev/null` を実行。成功または既存なら `REFINED_LABEL_OK=true`、失敗時は `REFINED_LABEL_OK=false` でワークフロー続行（ラベル非付与）。

`is_split_generated: true` の Issue には refined ラベルを付与してはならない（MUST NOT）。

### Step 2: ユーザー確認（MUST）

全候補を一覧表示する。quick 候補には `[quick]` マークを付与。ユーザーが承認するまで作成に進んではならない。

### Step 3: creation routing

- **通常（単一）**: `/twl:issue-create` を呼び出す
- **通常（複数）**: `/twl:issue-bulk-create` を呼び出す
- **クロスリポ**: `/twl:issue-cross-repo-create` を呼び出す

ラベル付与ルール:
- `REFINED_LABEL_OK=true` かつ `is_split_generated != true` → `--label refined`
- quick 条件充足 → `--label quick`

### Step 4: Project Board 同期

各 Issue 作成後に `/twl:project-board-sync N` を呼び出す。失敗は警告のみでワークフロー続行。

**MUST**: `chain-runner.sh board-status-update` を直接呼ばないこと（デフォルトが In Progress のため新規 Issue が誤って In Progress になる）。

### Step 5: クリーンアップ

`.controller-issue/` ディレクトリを削除する（中止時も同様）。

### Step 6: 完了通知

作成された Issue の URL を表示し、`/twl:workflow-setup #N` で開発開始を案内する。

## 禁止事項（MUST NOT）

- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
