## MODIFIED Requirements

### Requirement: state-write.sh 呼び出し形式の修正

all-pass-check.md および merge-gate.md 内の state-write.sh 呼び出しは、名前付きフラグ形式（`--type`, `--issue`, `--role`, `--set`）を使用しなければならない（SHALL）。

#### Scenario: all-pass-check が PASS 時に merge-ready へ遷移
- **WHEN** 全ステップが PASS または WARN のとき
- **THEN** `bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=merge-ready"` が実行される

#### Scenario: all-pass-check が FAIL 時に failed へ遷移
- **WHEN** いずれかのステップが FAIL のとき
- **THEN** `bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=failed"` が実行される

#### Scenario: merge-gate が PASS 時に done へ遷移
- **WHEN** BLOCKING findings が 0 件のとき
- **THEN** `bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role pilot --set "status=done"` および `--set "merged_at=..."` が実行される

#### Scenario: merge-gate が REJECT 時（1回目）に状態を更新
- **WHEN** BLOCKING findings が 1 件以上かつ retry_count が 0 のとき
- **THEN** `bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=failed"` に続き、retry_count, fix_instructions, status=running が順に書き込まれる

#### Scenario: merge-gate が REJECT 時（2回目）に確定失敗
- **WHEN** BLOCKING findings が 1 件以上かつ retry_count が 1 以上のとき
- **THEN** `bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role pilot --set "status=failed"` が実行される

### Requirement: DCI Context セクションの追加

all-pass-check.md、merge-gate.md、ac-verify.md には DCI Context セクションを配置しなければならない（MUST）。ref-dci.md の標準パターンに準拠する。

#### Scenario: all-pass-check に DCI Context が存在する
- **WHEN** all-pass-check.md を読み込むとき
- **THEN** ファイル先頭に `## Context (auto-injected)` セクションが存在し、BRANCH, ISSUE_NUM, PR_NUMBER が定義されている

#### Scenario: merge-gate に DCI Context が存在する
- **WHEN** merge-gate.md を読み込むとき
- **THEN** ファイル先頭に `## Context (auto-injected)` セクションが存在し、BRANCH, ISSUE_NUM, PR_NUMBER が定義されている

#### Scenario: ac-verify に DCI Context が存在する
- **WHEN** ac-verify.md を読み込むとき
- **THEN** ファイル先頭に `## Context (auto-injected)` セクションが存在し、ISSUE_NUM が定義されている

### Requirement: bare repo 互換の merge フロー

merge-gate.md の squash merge コマンドから `--delete-branch` フラグを除去しなければならない（MUST）。ブランチ削除は worktree-delete.sh にブランチ名を渡して委譲する。

#### Scenario: squash merge に --delete-branch が含まれない
- **WHEN** merge-gate が PASS 判定で squash merge を実行するとき
- **THEN** `gh pr merge ${PR_NUMBER} --squash` が実行され、`--delete-branch` は含まれない

#### Scenario: worktree-delete.sh にブランチ名が渡される
- **WHEN** merge-gate が merge 後に worktree を削除するとき
- **THEN** `bash scripts/worktree-delete.sh "${BRANCH}"` が実行される（フルパスではなくブランチ名）

## ADDED Requirements

### Requirement: worktree-create.sh の upstream 自動設定

worktree-create.sh は worktree 作成後、初回 push で upstream を自動設定しなければならない（SHALL）。

#### Scenario: 新規 worktree で upstream が設定される
- **WHEN** worktree-create.sh で新規ブランチを作成したとき
- **THEN** `git push -u origin <branch>` が実行され、upstream tracking が設定される

#### Scenario: upstream 設定失敗時は警告のみ
- **WHEN** `git push -u origin <branch>` が失敗したとき（ネットワークエラー等）
- **THEN** 警告メッセージを表示し、worktree 作成自体は成功する
