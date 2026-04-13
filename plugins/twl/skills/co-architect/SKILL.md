---
name: twl:co-architect
description: |
  対話的アーキテクチャ構築ワークフロー。
  explore を活用し architecture/ に設計意図を段階的にキャプチャ。
  branch 上で作業し PR 経由でレビュー・マージするフローを含む。
  完全性チェックまで実行し、Issue 化は co-issue に委譲。

  Use when user: says アーキテクチャ設計/architecture/全体設計,
  says 設計を構造化したい/Context分解/Phase計画,
  says --group/グループ深堀り/スケルトン精緻化.
type: controller
effort: high
tools: [Agent(worker-architecture, worker-structure), AskUserQuestion, Bash, Read, Skill, Write]
- Agent(worker-architecture, worker-structure)
spawnable_by:
- user
maxTurns: 60
---

# co-architect

対話的アーキテクチャ構築 → branch/PR + workflow-arch-review 経由マージ。Issue 化は co-issue に委譲。Non-implementation controller（chain-driven 不要）。

## Step 0: --group 分岐

`--group <context-name>` が含まれる場合:
→ `/twl:architect-group-refine <context-name>` を実行して終了（Step 1〜7 スキップ）。

`--group` なし → Step 1 へ。

## Step 1: コンテキスト収集

TaskCreate 「Architecture: コンテキスト収集」(status: in_progress)

プロジェクト概要を把握:
- README.md, CLAUDE.md, パッケージマネージャ設定を Read
- 既存 `architecture/` があれば Read して現状把握
- なければ `architecture/` ディレクトリを作成

TaskUpdate → completed

## Step 2: Worktree 作成 + 対話的アーキテクチャ探索

TaskCreate 「Architecture: Worktree 作成 + 対話的探索」(status: in_progress)

**Worktree 作成:**

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BRANCH="docs/arch-${TIMESTAMP}"
python3 -m twl.autopilot.worktree create "${BRANCH}"
```

作成した worktree ディレクトリに移動し、以下の探索を実施する。

**対話的探索（worktree 上）:**

`/twl:explore` を Skill tool で呼び出す。以下をコンテキストとして注入:

> アーキテクチャ探索モード: DDD の Bounded Context、ユビキタス言語、Context Map を使い設計を構造化。
> 確定した設計事項は architecture/ の対応ファイルに Write:
> - ビジョン → `architecture/vision.md`
> - ドメインモデル → `architecture/domain/model.md`
> - 用語定義 → `architecture/domain/glossary.md`
> - Bounded Context → `architecture/domain/contexts/<name>.md`
> - 設計判断 → `architecture/decisions/<NNNN>-<title>.md`
> - API 境界 → `architecture/contracts/<name>.md`

TaskUpdate → completed

## Step 3: 完全性チェック

TaskCreate 「Architecture: 完全性チェック」(status: in_progress)

`/twl:architect-completeness-check` を実行。

WARNING がある場合 → ユーザーに不足箇所を提示し補完するか確認。
補完する場合 → Step 2 の探索ループに戻る。

TaskUpdate → completed

## Step 4: ユーザー確認

**AskUserQuestion tool** で以下を提示:

> Architecture spec の探索が完了しました。次のアクションを選択してください:
> [A] PR を作成してレビューを開始する
> [B] 追加探索を続ける
> [C] 変更を破棄して終了する

- [A] → Step 5 へ
- [B] → Step 2 に戻り explore を再開
- [C] → worktree を削除して終了:
  ```bash
  bash plugins/twl/scripts/worktree-delete.sh "${BRANCH}"
  git push origin --delete "${BRANCH}" 2>/dev/null || true
  ```

## Step 5: PR 作成

TaskCreate 「Architecture: PR 作成」(status: in_progress)

worktree 上で commit + PR を作成する:

```bash
# worktree 内で実行（BRANCH 変数は Step 2 で設定済み）
git add -A
# コミットメッセージ: architecture/ 変更ファイルを確認して具体的な内容を記述
git commit -m "docs(architecture): <変更した context/decision/model 名を記述>"
git push origin "${BRANCH}"
PR_NUMBER=$(gh pr create --base main --head "${BRANCH}" \
  --title "docs(architecture): <変更内容の概要>" \
  --body "Architecture docs の更新。co-architect による自動作成。" \
  --json number -q '.number')
echo "${PR_NUMBER}" > /tmp/co-architect-pr-number.txt
echo "PR #${PR_NUMBER} を作成しました"
```

TaskUpdate → completed

## Step 6: workflow-arch-review 呼び出し

TaskCreate 「Architecture: レビュー実行」(status: in_progress)

`/twl:workflow-arch-review` を Skill tool で実行する。
PR 番号を取得してから引数として渡す:

```bash
PR_NUMBER=$(cat /tmp/co-architect-pr-number.txt 2>/dev/null || echo "")
```

`Skill("twl:workflow-arch-review", args="#${PR_NUMBER}")`

workflow-arch-review は以下を実行する:
- arch-phase-review（worker-arch-doc-reviewer + worker-architecture による並列レビュー）
- arch-fix-phase（CRITICAL/WARNING 修正）
- merge-gate（マージ判定）
- auto-merge（squash merge → cleanup）

TaskUpdate → completed

## Step 7: クリーンアップ

merge-gate が PASS してマージ完了した場合:

```bash
# worktree 削除 + remote branch 削除（BRANCH は Step 2 で設定）
bash plugins/twl/scripts/worktree-delete.sh "${BRANCH}"
git push origin --delete "${BRANCH}" 2>/dev/null || true
rm -f /tmp/co-architect-pr-number.txt
```

merge-gate が REJECT した場合:
- ユーザーに報告し、worktree を保持する
- 手動で修正後に `/twl:workflow-arch-review` を再実行するよう案内する

```
>>> Architecture spec 作成・マージ完了

次のステップ:
  - Issue 化: /twl:co-issue で architecture spec ベースに Issue 群を作成
  - autopilot: /twl:co-autopilot で Issue 群を一括実装
```

## 禁止事項（MUST NOT）

- ユーザーの設計判断を代替してはならない（UX ルール。提案は可、決定はユーザー）
- controller 内に実質処理を記述してはならない（設計ルール。atomic に委譲）
- main worktree に直接 Write してはならない（branch/PR 経由を必須とする）

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
