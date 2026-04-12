## 1. deltaspec-helpers.sh ライブラリ作成

- [x] 1.1 `plugins/twl/scripts/lib/deltaspec-helpers.sh` を新設し、`resolve_deltaspec_root()` を定義する
- [x] 1.2 パス解決を `BASH_SOURCE[0]` ベースで session-independent に実装する

## 2. chain-runner.sh のリファクタリング

- [x] 2.1 `chain-runner.sh` に `# shellcheck source=./lib/deltaspec-helpers.sh` ディレクティブと `source "${SCRIPT_DIR}/lib/deltaspec-helpers.sh"` を追加する
- [x] 2.2 `chain-runner.sh` 内の `resolve_deltaspec_root()` 定義を削除する

## 3. autopilot-orchestrator.sh のリファクタリング

- [x] 3.1 `autopilot-orchestrator.sh` に `# shellcheck source=./lib/deltaspec-helpers.sh` ディレクティブと `source "${SCRIPTS_ROOT}/lib/deltaspec-helpers.sh"` を追加する
- [x] 3.2 `_archive_deltaspec_changes_for_issue()` のインライン find ロジックを `resolve_deltaspec_root()` 呼び出しに置換する

## 4. bats テスト追加

- [x] 4.1 `test/bats/` に `deltaspec-helpers.bats` を追加し、`resolve_deltaspec_root` の 3 ケース（直下・walk-down・不在）をテストする
- [x] 4.2 `_archive_deltaspec_changes_for_issue` の回帰テストシナリオを追加する（単一 nested root での archive 維持）

## 5. shellcheck lint

- [x] 5.1 `shellcheck plugins/twl/scripts/chain-runner.sh` を通す
- [x] 5.2 `shellcheck plugins/twl/scripts/autopilot-orchestrator.sh` を通す
