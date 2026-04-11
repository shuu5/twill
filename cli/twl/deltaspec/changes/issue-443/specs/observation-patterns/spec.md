## ADDED Requirements

### Requirement: bug-deltaspec-archive パターン追加

`observation-pattern-catalog.md` に `bug-deltaspec-archive` パターンを追加しなければならない（SHALL）。パターン ID は `bug-deltaspec-archive`、category は `deltaspec-archive-failure`、related_issue は `"436"` でなければならない（SHALL）。

#### Scenario: bug-deltaspec-archive パターンが定義されている
- **WHEN** `observation-pattern-catalog.md` を読み込む
- **THEN** `bug-deltaspec-archive:` エントリが存在し、`regex`、`severity: error`、`category: deltaspec-archive-failure`、`related_issue: "436"` フィールドを持つ

#### Scenario: bug-deltaspec-archive regex が valid
- **WHEN** `echo "archive failed" | grep -E "$REGEX"` を実行する
- **THEN** exit code が 0 または 1（2 = invalid regex ではない）

### Requirement: bug-chain-stall パターン追加

`observation-pattern-catalog.md` に `bug-chain-stall` パターンを追加しなければならない（SHALL）。パターン ID は `bug-chain-stall`、category は `chain-transition-stall`、related_issue は `"438"` でなければならない（SHALL）。

#### Scenario: bug-chain-stall パターンが定義されている
- **WHEN** `observation-pattern-catalog.md` を読み込む
- **THEN** `bug-chain-stall:` エントリが存在し、`regex`、`severity: error`、`category: chain-transition-stall`、`related_issue: "438"` フィールドを持つ

#### Scenario: bug-chain-stall regex が valid
- **WHEN** `echo "chain stall detected" | grep -E "$REGEX"` を実行する
- **THEN** exit code が 0 または 1（2 = invalid regex ではない）

### Requirement: bug-phase-review-skip パターン追加

`observation-pattern-catalog.md` に `bug-phase-review-skip` パターンを追加しなければならない（SHALL）。パターン ID は `bug-phase-review-skip`、category は `phase-review-skip`、related_issue は `"439"` でなければならない（SHALL）。

#### Scenario: bug-phase-review-skip パターンが定義されている
- **WHEN** `observation-pattern-catalog.md` を読み込む
- **THEN** `bug-phase-review-skip:` エントリが存在し、`regex`、`severity: warning`、`category: phase-review-skip`、`related_issue: "439"` フィールドを持つ

#### Scenario: bug-phase-review-skip regex が valid
- **WHEN** `echo "phase-review skipped" | grep -E "$REGEX"` を実行する
- **THEN** exit code が 0 または 1（2 = invalid regex ではない）

### Requirement: bats テスト更新（bug- プレフィックス対応）

`tests/bats/refs/observation-references.bats` を更新し、`bug-` プレフィックスパターン数の検証を追加しなければならない（SHALL）。

#### Scenario: bug- プレフィックスパターンが bats テストで検証される
- **WHEN** `observation-references.bats` を実行する
- **THEN** `bug-` プレフィックスのパターン数が 3 以上であることを検証し、全テストが PASS する

## MODIFIED Requirements

### Requirement: 全パターン数カウント閾値更新

`observation-references.bats` の total パターン数閾値を `bug-` プレフィックス追加分（3）を加えた値に更新しなければならない（SHALL）。

#### Scenario: total パターン数が更新後の閾値を満たす
- **WHEN** `observation-references.bats` の `has at least 9 patterns across all categories` テストを実行する
- **THEN** `error-` + `warn-` + `info-` + `hist-` + `bug-` の合計が 12 以上で PASS する
