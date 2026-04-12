## 1. 共通ヘルパー新設 (A)

- [ ] 1.1 `plugins/twl/scripts/lib/gh-read-content.sh` を新設し `gh_read_issue_full` / `gh_read_pr_full` 関数を実装する
- [ ] 1.2 `deps.yaml` に `gh-read-content.sh` を `lib` カテゴリで追加する
- [ ] 1.3 `twl check` が PASS することを確認する

## 2. B-1 gap 修正 — scripts

- [ ] 2.1 `scripts/ac-checklist-gen.sh` の body のみ取得を `gh_read_issue_full` 経由に修正する
- [ ] 2.2 `scripts/chain-runner.sh` L332 の retroactive_propose implementation_pr 抽出を `gh_read_issue_full` 経由に修正する
- [ ] 2.3 `scripts/pr-link-issue.sh` L96 の PR body 取得を `gh_read_pr_full` 経由に修正する

## 3. B-1 gap 修正 — agents / commands

- [ ] 3.1 `agents/worker-issue-pr-alignment.md` L30, L39 の body のみ取得を `gh_read_issue_full` / `gh_read_pr_full` 経由に修正する
- [ ] 3.2 `commands/issue-cross-repo-create.md` L124 の parent body のみ取得を `gh_read_issue_full` 経由に修正する
- [ ] 3.3 `commands/autopilot-multi-source-verdict.md` L42 の切り詰め（`[:1024]`、`[-5:]`）を撤廃し full content を使用するよう修正する

## 4. B-2 個別実装を共通ヘルパー経由に統一

- [ ] 4.1 `scripts/autopilot-plan.sh` L182-193 (`issue_touches_deps_yaml`) を `gh_read_issue_full` 経由に書き換える
- [ ] 4.2 `scripts/autopilot-plan.sh` L409-420（依存関係検出ループ）を `gh_read_issue_full` 経由に書き換える

## 5. C — workflow-issue-refine への comments 注入

- [ ] 5.1 `skills/workflow-issue-refine/SKILL.md` Step 3a で Issue comments を取得して specialist に渡すよう修正する
- [ ] 5.2 `commands/issue-structure.md` の入力仕様に comments を追加する
- [ ] 5.3 `commands/issue-spec-review.md` の specialist prompt に `### === Issue Comments ===` セクションを追加する

## 6. D — ドキュメント・型ルール更新

- [ ] 6.1 `plugins/twl/refs/ref-gh-read-policy.md` を新設し content-reading vs meta-only の型ルールを記述する
- [ ] 6.2 `architecture/domain/contexts/issue-mgmt.md` に IM-8 として本ポリシーを追記する

## 7. E — テスト

- [ ] 7.1 `tests/bats/scripts/gh-read-content.bats` を新設し `gh_read_issue_full` / `gh_read_pr_full` の単体テストを実装する
- [ ] 7.2 `tests/scenarios/gh-body-comments-policy.test.sh` を新設し静的検査で全 gap 箇所が helper 経由に移行済みであることを確認する
- [ ] 7.3 BATS テストおよびシナリオテストが PASS することを確認する

## 8. 最終確認

- [ ] 8.1 `rg "gh issue view.*--json body" plugins/twl` の hit が meta-only 箇所のみ（content-reading 用途は 0 件）であることを確認する
- [ ] 8.2 `twl check` が PASS することを確認する
- [ ] 8.3 `twl update-readme` を実行する
