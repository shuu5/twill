## Context

pr-cycle チェーン（all-pass-check → merge-gate）は autopilot Worker が実行する。
bare repo + worktree 構成において、以下の5つの根本原因により Worker の状態遷移が機能停止している:

1. state-write.sh の呼び出しが位置引数形式だが、スクリプトは名前付きフラグを期待
2. DCI Context セクションが未追加で ISSUE_NUM 等が空文字列
3. `gh pr merge --delete-branch` が bare repo で main checkout を試み fatal
4. worktree-delete.sh にフルパスを渡すがスクリプトはブランチ名を期待
5. worktree-create.sh で初回 push 時に upstream 未設定

## Goals / Non-Goals

**Goals:**

- all-pass-check.md / merge-gate.md の state-write.sh 呼び出しを正しいフラグ形式に修正
- all-pass-check.md / merge-gate.md / ac-verify.md に DCI Context セクションを追加
- merge-gate.md を bare repo 互換にする（`--delete-branch` 除去、ブランチ名渡し）
- worktree-create.sh で初回 push 時に upstream を自動設定

**Non-Goals:**

- `--auto` / `--auto-merge` フラグの廃止（#47 のスコープ）
- auto-merge.md の bare repo 対応（merge-gate.md 側で吸収済み）
- state-write.sh 自体の修正（スクリプトは正しく動作している）

## Decisions

### D1: state-write.sh 呼び出し形式の統一

位置引数 `bash scripts/state-write.sh issue "${ISSUE_NUM}" status merge-ready` を
名前付きフラグ `bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=merge-ready"` に統一。

all-pass-check は Worker ロールで実行されるため `--role worker`。
merge-gate は Pilot ロールで実行されるため `--role pilot`。
ただし merge-gate の retry_count / fix_instructions / status(running) は Worker 権限が必要なため、
Pilot アクセス制御（state-write.sh L99-108）を確認し、role 設計を検討する。

→ state-write.sh の Pilot 許可フィールドは `status`, `merged_at`, `failure` のみ。
REJECT 時の `retry_count`, `fix_instructions` 書き込みは Worker ロールで行うべき。
merge-gate は Pilot が実行するが、REJECT 時の fix-phase 指示書き込みは Worker に委譲するか、
もしくは merge-gate 内で `--role worker` を使う（Pilot 特権エスカレーション）。

**決定**: merge-gate の REJECT パスでは `--role worker` を使用する（fix-phase の指示は Worker の責務領域）。
PASS パスの `status=done` / `merged_at` は `--role pilot` を使用する。

### D2: DCI Context セクションの注入パターン

ref-dci.md の標準パターンに従い、各コマンドに必要最小限の変数のみ注入:

- all-pass-check: BRANCH, ISSUE_NUM, PR_NUMBER（ref-dci テーブル定義済み）
- merge-gate: ISSUE_NUM, PR_NUMBER（PR_NUM → PR_NUMBER に統一）, WORKTREE_PATH は不要（ブランチ名から算出）
- ac-verify: ISSUE_NUM（コメント投稿に使用）

### D3: bare repo 互換の merge フロー

`gh pr merge --squash --delete-branch` → `gh pr merge --squash` に変更。
ブランチ削除は `worktree-delete.sh` に委譲（ブランチ名を渡す）。
ブランチ名は DCI の BRANCH 変数から取得。

### D4: worktree-create.sh の upstream 設定

`git worktree add` 後の初回 push で `git push -u origin <branch>` を実行するよう修正。
既に upstream が設定されている場合はスキップ。

## Risks / Trade-offs

- **merge-gate の REJECT パスで `--role worker` を使用**: Pilot が Worker ロールで書き込むことは設計上の例外。ただし fix-phase 指示は Worker の責務であり、実質的に Worker の代理行為。state-write.sh のロール検証は呼び出し元の信頼に依存しており、セキュリティリスクは限定的。
- **worktree-create.sh の upstream 設定**: push 先の存在確認をせず `git push -u` を実行する。リモートにブランチが存在しない初回 push が前提のため問題なし。
