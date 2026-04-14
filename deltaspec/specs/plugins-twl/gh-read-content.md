## Requirements

### Requirement: gh-read-content ヘルパー新設

`plugins/twl/scripts/lib/gh-read-content.sh` を新設し、`gh_read_issue_full` と `gh_read_pr_full` 関数を定義しなければならない（SHALL）。

- 各関数は body と全 comments を結合した単一テキストを標準出力しなければならない（SHALL）。
- 切り詰め（character/line 制限）を行ってはならない（SHALL NOT）。
- `--repo <R>` オプションを受け付け cross-repo 読み込みに対応しなければならない（SHALL）。
- body または comments の取得に失敗した場合は空文字列を返し、stderr に警告を出力しなければならない（SHALL）。

#### Scenario: 正常取得
- **WHEN** `gh_read_issue_full 499 --repo shuu5/twill` を呼び出す
- **THEN** body テキスト + `## === Comments ===` セパレータ + 全 comments テキストが標準出力に返る

#### Scenario: cross-repo 取得
- **WHEN** `gh_read_issue_full 486 --repo shuu5/twill` を cross-repo 環境で呼び出す
- **THEN** 指定リポジトリの Issue body + comments が取得される

#### Scenario: エラー時フォールバック
- **WHEN** 存在しない Issue 番号を指定する
- **THEN** 空文字列が標準出力に返り、stderr に警告メッセージが出力される

### Requirement: 共通ヘルパーの deps.yaml 登録

`gh-read-content.sh` を `deps.yaml` の `lib` カテゴリに追加しなければならない（SHALL）。

#### Scenario: deps.yaml 反映
- **WHEN** `twl check` を実行する
- **THEN** `gh-read-content.sh` が deps.yaml に登録済みとして検証が通る

### Requirement: B-1 gap 修正 — ac-checklist-gen.sh

`scripts/ac-checklist-gen.sh` の body のみ取得を `gh_read_issue_full` 経由に置き換えなければならない（SHALL）。

#### Scenario: comments 記載の AC を取得できる
- **WHEN** Issue body ではなく comments に AC が記載されている Issue で ac-checklist-gen.sh を実行する
- **THEN** comments の AC が checklist に含まれる

### Requirement: B-1 gap 修正 — chain-runner.sh L332

`chain-runner.sh` L332 の retroactive_propose implementation_pr 抽出を `gh_read_issue_full` 経由に置き換えなければならない（SHALL）。

#### Scenario: comments から implementation_pr を検出できる
- **WHEN** Issue の comments に `implementation_pr` の参照が記載されている
- **THEN** chain-runner.sh が comments から implementation_pr を抽出できる

### Requirement: B-1 gap 修正 — pr-link-issue.sh L96

`pr-link-issue.sh` L96 の PR body 取得を `gh_read_pr_full` 経由に置き換えなければならない（SHALL）。

#### Scenario: PR comments の制約を確認できる
- **WHEN** PR の comments に制約が記載されている
- **THEN** pr-link-issue.sh が comments を含めた PR 内容を取得できる

### Requirement: B-1 gap 修正 — worker-issue-pr-alignment.md

`agents/worker-issue-pr-alignment.md` (L30, L39) の body のみ取得を `gh_read_issue_full` / `gh_read_pr_full` 経由に置き換えなければならない（SHALL）。

#### Scenario: comments を含む整合性レビュー
- **WHEN** Issue の整合性レビューで comments に仕様追記がある
- **THEN** worker-issue-pr-alignment が comments を含めて整合性を判断する

### Requirement: B-1 gap 修正 — issue-cross-repo-create.md L124

`commands/issue-cross-repo-create.md` L124 の parent body のみ取得を `gh_read_issue_full` 経由に置き換えなければならない（SHALL）。

#### Scenario: parent comments を子 Issue に継承できる
- **WHEN** parent Issue の comments に子 Issue に引き継ぐべき仕様が記載されている
- **THEN** cross-repo 子 Issue 作成時に parent comments が参照される

### Requirement: B-1 gap 修正 — autopilot-multi-source-verdict.md L42 切り詰め撤廃

`commands/autopilot-multi-source-verdict.md` L42 の切り詰め（`[:1024]`、`[-5:]`）を撤廃し、full body + all comments を使用しなければならない（SHALL）。

#### Scenario: 全 comments を verdict に使用できる
- **WHEN** Issue の古い comments に重要な制約がある
- **THEN** autopilot-multi-source-verdict が切り詰めなしで全 comments を verdict 判断に使用する

### Requirement: B-2 統一 — autopilot-plan.sh

`scripts/autopilot-plan.sh` (L182-193 `issue_touches_deps_yaml`、L409-420 依存検出ループ) の個別実装を `gh_read_issue_full` 経由に置き換えなければならない（SHALL）。機能退行が許されない（SHALL NOT）。

#### Scenario: issue_touches_deps_yaml が comments 記載の deps.yaml 変更を検出できる
- **WHEN** deps.yaml 変更が Issue の comments に記載されている
- **THEN** `issue_touches_deps_yaml` が comments を参照して変更を検出する

### Requirement: C — workflow-issue-refine への comments 注入

`skills/workflow-issue-refine/SKILL.md` Step 3a で Issue comments を specialist に注入しなければならない（SHALL）。

- `commands/issue-structure.md` の入力に comments を追加しなければならない（SHALL）。
- `commands/issue-spec-review.md` の specialist prompt に `### === Issue Comments ===` セクションを追加しなければならない（SHALL）。

#### Scenario: comments 記載の仕様が refinement に反映される
- **WHEN** Issue の comments に追加 AC が記載されている
- **THEN** workflow-issue-refine の refinement 結果に comments 記載の AC が反映される

### Requirement: D — ドキュメント・型ルール更新

`refs/ref-gh-read-policy.md` を新設し、content-reading は body + comments 必須、meta-only は属性取得のみという型ルールを明記しなければならない（SHALL）。

`architecture/domain/contexts/issue-mgmt.md` に IM-8 として本ポリシーを追記しなければならない（SHALL）。

#### Scenario: 型ルール参照で対象外を判断できる
- **WHEN** 開発者が新しい gh 読み込みコードを書く
- **THEN** `ref-gh-read-policy.md` を参照することで content-reading か meta-only かを判断できる

### Requirement: E — テスト

`tests/bats/scripts/gh-read-content.bats` を新設し、`gh_read_issue_full` / `gh_read_pr_full` の単体テストが PASS しなければならない（SHALL）。

`tests/scenarios/gh-body-comments-policy.test.sh` を新設し、全 gap 箇所が helper 経由に移行済みであることを静的検査で確認しなければならない（SHALL）。

#### Scenario: ヘルパー単体テストが PASS する
- **WHEN** `bats tests/bats/scripts/gh-read-content.bats` を実行する
- **THEN** 全テストが PASS する

#### Scenario: 静的検査で gap が 0 件になる
- **WHEN** `tests/scenarios/gh-body-comments-policy.test.sh` を実行する
- **THEN** content-reading 用途で `--json body` のみを使用している箇所が 0 件と報告される
