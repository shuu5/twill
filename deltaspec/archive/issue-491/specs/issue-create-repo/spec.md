## MODIFIED Requirements

### Requirement: issue-create --repo オプション追加

`plugins/twl/commands/issue-create.md` に `--repo <owner/repo>` オプションが追加されなければならない（SHALL）。未指定時は現在のリポジトリへ作成する既存動作を維持しなければならない（MUST）。

#### Scenario: --repo 未指定時の後方互換
- **WHEN** `--repo` を指定せずに issue-create を呼ぶ
- **THEN** 現在のリポジトリへ `gh issue create` を実行する（既存動作と同一）

#### Scenario: --repo 指定時の cross-repo 起票
- **WHEN** `--repo owner/repo` を指定して issue-create を呼ぶ
- **THEN** `gh issue create -R owner/repo --body-file <tempfile>` を使用して指定リポへ起票する

### Requirement: --repo 指定時の --body-file セキュリティパターン

`--repo` 指定時は本文を `--body-file` 経由で渡さなければならない（SHALL）。issue-cross-repo-create.md の security allow-list パターンに従わなければならない（MUST）。

#### Scenario: body-file 経由渡し
- **WHEN** `--repo` が指定されている
- **THEN** 本文をテンポラリファイルに書き出し `--body-file` で渡す
