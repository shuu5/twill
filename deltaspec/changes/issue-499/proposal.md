## Why

twill plugin 内で Issue/PR の内容理解を目的とする `gh` 読み込み箇所が body のみを取得し comments を読み飛ばしているケースが複数存在する。ユーザーが comments に追記した仕様・AC・制約・議論結果がワークフローから見えない盲点となっており、refinement / autopilot の判断品質を毀損している。

## What Changes

- `plugins/twl/scripts/lib/gh-read-content.sh` を新設し、`gh_read_issue_full` / `gh_read_pr_full` 関数を定義する
- 既存の 6 箇所の comments 取りこぼし gap を共通ヘルパー経由に修正する（B-1）
- 既に body + comments を取得しているが個別実装の 2 箇所を共通ヘルパー経由に統一する（B-2）
- `workflow-issue-refine` の Step 3a で Issue comments を specialist に注入する（C）
- `refs/ref-gh-read-policy.md` を新設し、content-reading vs meta-only の型ルールを文書化する（D）
- `issue-mgmt.md` に IM-8 として本ポリシーを追記する（D）
- `tests/bats/scripts/gh-read-content.bats` および `tests/scenarios/gh-body-comments-policy.test.sh` を新設する（E）

## Capabilities

### New Capabilities

- `gh_read_issue_full <issue> [--repo <R>]`: Issue body + 全 comments を結合した単一テキストを標準出力（切り詰めなし）
- `gh_read_pr_full <pr> [--repo <R>]`: PR body + 全 comments を結合した単一テキストを標準出力（切り詰めなし）
- `ref-gh-read-policy.md`: content-reading（body + comments 必須）vs meta-only（属性取得のみ）の型ルール定義
- `gh-body-comments-policy.test.sh`: 静的検査で全 gap 箇所が helper 経由に移行済みであることを確認

### Modified Capabilities

- `ac-checklist-gen.sh`: body のみ → `gh_read_issue_full` 経由に変更
- `chain-runner.sh` (L332): retroactive_propose の implementation_pr 抽出を共通ヘルパー経由に変更
- `pr-link-issue.sh` (L96): PR 本文書き換え前の確認を `gh_read_pr_full` 経由に変更
- `worker-issue-pr-alignment.md` (L30, L39): body のみ → `gh_read_issue_full` + `gh_read_pr_full` 経由に変更
- `issue-cross-repo-create.md` (L124): parent body のみ → `gh_read_issue_full` 経由に変更
- `autopilot-multi-source-verdict.md` (L42): 切り詰め撤廃、full body + all comments を使用
- `autopilot-plan.sh` (L182-193, L409-420): 個別実装 → `gh_read_issue_full` 経由に統一
- `workflow-issue-refine` Step 3a: Issue body + comments を specialist に注入
- `issue-structure.md`: comments を入力として受け付ける拡張
- `issue-spec-review.md`: specialist prompt に comments セクションを注入
- `issue-mgmt.md`: IM-8 追記

## Impact

- `plugins/twl/scripts/lib/` に新規ファイル追加（deps.yaml 更新必要）
- 既存スクリプト 3 件・agent 1 件・command 3 件・skill 1 件の修正
- `tests/bats/` および `tests/scenarios/` にテスト追加
- `refs/` および `architecture/domain/contexts/` にドキュメント追加
- `twl check` と `twl update-readme` の再実行が必要
