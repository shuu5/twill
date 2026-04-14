## ADDED Requirements

### Requirement: deltaspec-helpers ライブラリの新設
`plugins/twl/scripts/lib/deltaspec-helpers.sh` を新設し、`resolve_deltaspec_root()` 関数を定義しなければならない（SHALL）。
関数は `chain-runner.sh` の既存実装と完全に同一の挙動を持たなければならない（SHALL）。
パス解決は `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` ベースで行い、session-independent でなければならない（MUST）。

#### Scenario: 直下に deltaspec/config.yaml がある場合
- **WHEN** `resolve_deltaspec_root "$root"` を呼び出し、`$root/deltaspec/config.yaml` が存在する
- **THEN** `$root` を echo して return 0 する

#### Scenario: walk-down fallback で deltaspec/config.yaml が見つかる場合
- **WHEN** `resolve_deltaspec_root "$root"` を呼び出し、直下には config.yaml がないが maxdepth=5 以内に `*/deltaspec/config.yaml` が存在する
- **THEN** その config.yaml の親ディレクトリの親ディレクトリ（deltaspec root）を echo して return 0 する

#### Scenario: deltaspec/config.yaml が見つからない場合
- **WHEN** `resolve_deltaspec_root "$root"` を呼び出し、maxdepth=5 以内に config.yaml が存在しない
- **THEN** `$root` を echo して return 1 する

### Requirement: chain-runner.sh の resolve_deltaspec_root 共有化
`chain-runner.sh` から `resolve_deltaspec_root()` の定義を削除し、`lib/deltaspec-helpers.sh` を source しなければならない（SHALL）。
source 行は `source "${SCRIPT_DIR}/lib/deltaspec-helpers.sh"` の形式で、既存の lib source パターンに倣わなければならない（MUST）。
shellcheck ディレクティブ `# shellcheck source=./lib/deltaspec-helpers.sh` を追加しなければならない（SHALL）。

#### Scenario: chain-runner.sh が deltaspec-helpers.sh を source する
- **WHEN** `bash chain-runner.sh` が実行される
- **THEN** `resolve_deltaspec_root()` が正常に呼び出せる（既存の step_init の挙動が維持される）

### Requirement: autopilot-orchestrator.sh のインライン find 除去
`autopilot-orchestrator.sh` の `_archive_deltaspec_changes_for_issue()` 内のインライン walk-down find ロジックを削除し、`resolve_deltaspec_root()` 呼び出しに置換しなければならない（SHALL）。
`lib/deltaspec-helpers.sh` を source しなければならない（SHALL）。
`# shellcheck source=./lib/deltaspec-helpers.sh` ディレクティブを追加しなければならない（SHALL）。

#### Scenario: _archive_deltaspec_changes_for_issue が resolve_deltaspec_root を使う
- **WHEN** `_archive_deltaspec_changes_for_issue "$issue"` が呼び出される
- **THEN** インライン find の代わりに `resolve_deltaspec_root()` で `ds_root` を解決し、既存の archive 処理が正常に実行される

#### Scenario: shellcheck が両スクリプトを通過する
- **WHEN** `shellcheck plugins/twl/scripts/chain-runner.sh` および `shellcheck plugins/twl/scripts/autopilot-orchestrator.sh` を実行する
- **THEN** エラーなしで終了する（警告のみは許容）

### Requirement: bats 回帰テストの追加
bats テストで「DRY 解消後も既存の挙動（単一 nested root での archive）が維持される」シナリオを追加しなければならない（SHALL）。
`test/bats/` 配下の適切なファイルに追加しなければならない（MUST）。

#### Scenario: deltaspec-helpers.sh の resolve_deltaspec_root テスト
- **WHEN** bats テストで `resolve_deltaspec_root` を呼び出す
- **THEN** 直下・walk-down・不在の 3 ケースが正しく動作する
