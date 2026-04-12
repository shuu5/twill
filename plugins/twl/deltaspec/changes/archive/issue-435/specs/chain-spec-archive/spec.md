## MODIFIED Requirements

### Requirement: chain-runner.sh deltaspec 判定の config.yaml ベース化

`chain-runner.sh` の init ステップは `deltaspec/config.yaml` が存在する場合のみ `deltaspec=true` と判定しなければならない（SHALL）。config.yaml のない `deltaspec/` ディレクトリは deltaspec なしとして扱わなければならない（SHALL）。

#### Scenario: config.yaml なし deltaspec/ の無視
- **WHEN** worktree root に `deltaspec/`（config.yaml なし）が存在し、`plugins/twl/deltaspec/config.yaml` が存在する場合
- **THEN** `deltaspec=true` と判定し、`plugins/twl/deltaspec/` を正規の root として扱う

#### Scenario: config.yaml あり deltaspec/ の検出
- **WHEN** `find_deltaspec_root()` が有効な deltaspec root を返す場合
- **THEN** `chain-runner.sh` は `deltaspec=true` と判定する

### Requirement: auto-merge.sh の spec-archive 自動実行

`auto-merge.sh` は squash merge 成功後、`change_id` が存在する場合に `twl spec archive <change_id>` を実行しなければならない（SHALL）。spec-archive 失敗は PR merge 処理をブロックしてはならない（SHALL NOT）。

#### Scenario: merge 後の spec 自動統合
- **WHEN** squash merge が成功し、`change_id` が設定されている場合
- **THEN** `twl spec archive $change_id --yes` を実行し、成功した場合は deltaspec への変更をコミット・プッシュする

#### Scenario: spec-archive 失敗時のフォールバック
- **WHEN** `twl spec archive` が失敗する場合
- **THEN** WARNING ログを出力し、merge 処理は正常完了とする

## ADDED Requirements

### Requirement: autopilot-orchestrator の specs 統合有効化

`autopilot-orchestrator.sh` の `archive_done_issues()` は specs 統合付きで archive を実行しなければならない（SHALL）。specs 統合が失敗した場合は `--skip-specs` フォールバック + WARNING ログを出力しなければならない（SHALL）。

#### Scenario: specs 統合付き archive
- **WHEN** `archive_done_issues()` が Issue を archive する場合
- **THEN** `--skip-specs` なしで `twl spec archive` を実行し、specs を統合する

#### Scenario: specs 統合失敗時のフォールバック
- **WHEN** specs 統合（`twl spec archive`）が失敗する場合
- **THEN** `--skip-specs` で再実行し、WARNING ログを出力する。archive 処理自体はブロックしない
