## ADDED Requirements

### Requirement: worktree-health-check スクリプト

`plugins/twl/scripts/worktree-health-check.sh` を追加し、bare repo および全 worktree の `remote.origin.fetch` refspec を検査しなければならない（SHALL）。スクリプトは `--fix` オプションで欠落 refspec を自動修復しなければならない（SHALL）。

#### Scenario: refspec 欠落の検出
- **WHEN** `.bare/config` または任意の worktree で `remote.origin.fetch` が `+refs/heads/*:refs/remotes/origin/*` を含まない
- **THEN** `worktree-health-check.sh` が `WARN` メッセージを標準出力に出力し exit code 1 で終了する

#### Scenario: --fix による自動修復
- **WHEN** `worktree-health-check.sh --fix` を実行し、欠落 refspec が検出された
- **THEN** 影響 worktree それぞれに `git config --replace-all remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'` を適用し、exit code 0 で終了する

#### Scenario: 全 OK の場合
- **WHEN** `.bare/config` と全 worktree の `remote.origin.fetch` が正しく設定されている
- **THEN** `worktree-health-check.sh` が `OK` メッセージを出力し exit code 0 で終了する

### Requirement: origin/main tip 一致検査

`worktree-health-check.sh` はネットワーク利用可能時に `git show-ref refs/remotes/origin/main` と `git ls-remote origin main` の tip を比較しなければならない（SHALL）。ネットワーク不可時はタイムアウト（5 秒）後にスキップしなければならない（SHALL）。

#### Scenario: stale origin/main の検出
- **WHEN** ローカルの `refs/remotes/origin/main` が `git ls-remote origin main` のリモート tip と異なる
- **THEN** `WARN: origin/main is stale` を標準出力に出力する（非 blocking）

### Requirement: worktree-create での refspec 自動設定

`chain-runner.sh` の `step_worktree_create()` は worktree 作成完了後に `remote.origin.fetch` refspec を `+refs/heads/*:refs/remotes/origin/*` に設定しなければならない（SHALL）。

#### Scenario: 新規 worktree 作成後の refspec 設定
- **WHEN** `chain-runner.sh worktree-create` が新規 worktree の作成に成功した
- **THEN** 新規 worktree で `git config --get-all remote.origin.fetch` が `+refs/heads/*:refs/remotes/origin/*` を返す

#### Scenario: 既存正常 refspec の保持
- **WHEN** 新規 worktree で既に `remote.origin.fetch = +refs/heads/*:refs/remotes/origin/*` が設定されている
- **THEN** 重複エントリを追加しない（`--replace-all` を使用する）

## MODIFIED Requirements

### Requirement: autopilot-pilot-precheck への統合

`autopilot-pilot-precheck.md` は既存チェック（PR diff stat / AC spot-check）の前に refspec チェックを実行しなければならない（SHALL）。欠落検出時は `PRECHECK_WARNINGS` に追加し処理を継続しなければならない（SHALL）。abort してはならない（MUST NOT）。

#### Scenario: precheck 中の refspec 欠落検出
- **WHEN** `autopilot-pilot-precheck` 実行時に任意の worktree で refspec が欠落している
- **THEN** `WARN: fetch refspec missing in <path>` を `PRECHECK_WARNINGS` に追加し、後続の PR diff / AC チェックを継続する

### Requirement: CLAUDE.md Bare repo 構造検証の更新

`plugins/twl/CLAUDE.md` の「Bare repo 構造検証」セクションは refspec 条件を第 4 条件として含まなければならない（SHALL）。

#### Scenario: 第 4 条件の明文化
- **WHEN** 開発者が `plugins/twl/CLAUDE.md` の Bare repo 構造検証セクションを参照する
- **THEN** 「`.bare/config` および全 worktree の `remote.origin.fetch` が `+refs/heads/*:refs/remotes/origin/*` を含む」が 4 番目の条件として記載されている

## ADDED Requirements

### Requirement: bats テスト — refspec 欠落検出

bats テストシナリオで `worktree-health-check.sh` の動作を機械的に検証しなければならない（SHALL）。

#### Scenario: テスト setup で refspec を削除して欠落を模擬
- **WHEN** 一時 bare repo と worktree を作成し `git config --unset remote.origin.fetch` で refspec を削除した後 `worktree-health-check.sh` を実行する
- **THEN** exit code 1 かつ stdout に `WARN` が含まれる

#### Scenario: --fix 後に refspec が正しく設定される
- **WHEN** refspec が欠落した worktree で `worktree-health-check.sh --fix` を実行する
- **THEN** exit code 0 かつ `git config --get-all remote.origin.fetch` が `+refs/heads/*:refs/remotes/origin/*` を返す
