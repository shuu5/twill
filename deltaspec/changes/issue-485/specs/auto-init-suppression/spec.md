## ADDED Requirements

### Requirement: auto-init 抑制ガード（Phase 1）
`twl spec new` が `DeltaspecNotFound` を受けた際、`origin/main` に nested `deltaspec/config.yaml` が存在し、かつ `TWL_SPEC_ALLOW_AUTO_INIT` 環境変数が設定されていない場合、auto-init を発動せず終了コード 1 で失敗しなければならない（SHALL）。エラーメッセージには「nested deltaspec root が origin/main に存在しますが cwd から参照できません」、`cd <nested-root-parent>` または `git rebase origin/main` の実行案内を含めなければならない（SHALL）。

#### Scenario: nested root 存在時に auto-init を発動しない
- **WHEN** `find_deltaspec_root()` が `DeltaspecNotFound` を raise し、かつ `git ls-tree origin/main` 出力に `*/deltaspec/config.yaml` が含まれ、かつ `TWL_SPEC_ALLOW_AUTO_INIT` 未設定
- **THEN** `deltaspec/` ディレクトリが作成されず、エラーメッセージを stderr に出力し、exit code 1 で終了する

#### Scenario: TWL_SPEC_ALLOW_AUTO_INIT=1 で従来動作を維持
- **WHEN** `find_deltaspec_root()` が `DeltaspecNotFound` を raise し、かつ `TWL_SPEC_ALLOW_AUTO_INIT=1` が設定されている
- **THEN** 従来の auto-init フローが実行され、`deltaspec/` が cwd に作成される

### Requirement: origin/main アクセス失敗時のフォールバック
`git ls-tree origin/main` が失敗した場合（offline、`origin` 未設定等）、`twl spec new` は WARN メッセージを出力した上で従来の auto-init にフォールバックしなければならない（SHALL）。コマンド全体が abort されてはならない（MUST NOT）。

#### Scenario: offline 環境でのフォールバック
- **WHEN** `git ls-tree origin/main` が非ゼロ exit code を返す
- **THEN** stderr に `[WARN] origin/main へのアクセスに失敗しました。auto-init を続行します。` を出力し、従来の auto-init を実行する

## MODIFIED Requirements

### Requirement: find_deltaspec_root エラーメッセージ強化
`find_deltaspec_root()` が `DeltaspecNotFound` を raise する際、エラーメッセージに walk-up の開始パス・git top・walk-down の探索範囲・`git rebase origin/main` 推奨を含めなければならない（SHALL）。

#### Scenario: walk-up/walk-down 両方失敗時の詳細エラー
- **WHEN** walk-up と walk-down の両方で `deltaspec/config.yaml` が見つからない
- **THEN** エラーメッセージに `Walked up from: <path>`、`Searched git root: <git_top or "(no .git found)">`、`Hint: git rebase origin/main を検討してください` を含む `DeltaspecNotFound` が raise される

### Requirement: chain-runner step_init rebase ガード
`chain-runner.sh` の `step_init` は `plugins/twl/deltaspec/config.yaml` または `cli/twl/deltaspec/config.yaml` が見つからない場合、WARN ログを出力しなければならない（SHALL）。ただし init フロー自体を abort してはならない（MUST NOT）。

#### Scenario: nested config.yaml 欠落時に WARN を出力
- **WHEN** `step_init` 実行時に `plugins/twl/deltaspec/config.yaml` または `cli/twl/deltaspec/config.yaml` が存在しない
- **THEN** `[WARN] nested deltaspec config が見つかりません: <ファイルパス>` と `[WARN] git rebase origin/main を推奨します` が出力され、init フローは継続する

#### Scenario: 両 config.yaml 存在時は WARN なし
- **WHEN** `step_init` 実行時に `plugins/twl/deltaspec/config.yaml` と `cli/twl/deltaspec/config.yaml` の両方が存在する
- **THEN** rebase ガードの WARN は出力されない

## ADDED Requirements

### Requirement: unit test — nested root 存在時の auto-init 抑制
`cli/twl/tests/spec/test_new.py` に nested root が存在する状況で auto-init fallback が発動しないことを検証するテストを追加しなければならない（SHALL）。

#### Scenario: test_new_auto_init_suppressed_when_nested_root_exists
- **WHEN** `git ls-tree origin/main` が `plugins/twl/deltaspec/config.yaml` を含む出力を返すようモック化され、`find_deltaspec_root()` が `DeltaspecNotFound` を raise する
- **THEN** `cmd_new("issue-xxx")` が exit code 1 を返し、`deltaspec/` ディレクトリが作成されていない

#### Scenario: test_new_auto_init_allowed_with_env_var
- **WHEN** `TWL_SPEC_ALLOW_AUTO_INIT=1` が設定され、`find_deltaspec_root()` が `DeltaspecNotFound` を raise する
- **THEN** `cmd_new("issue-xxx")` が exit code 0 を返し、`deltaspec/changes/issue-xxx/` が作成される
