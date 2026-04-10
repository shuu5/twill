## Why

`plugins/twl/tests/scenarios/skillmd-pilot-fixes.test.sh` が 342 行（ベースライン警告閾値 300 行超過）に達しており、テスト可読性と保守性が低下している。Issue #387 PR verify の warning-fix フェーズで検出された。

## What Changes

- `plugins/twl/tests/helpers/test-common.sh` を新規作成し、共通ヘルパー関数（`assert_file_exists`, `assert_file_contains`, `assert_file_not_contains`, `run_test`, `run_test_skip`, カウンター初期化・サマリー出力）を切り出す
- `plugins/twl/tests/scenarios/skillmd-pilot-fixes.test.sh` をリファクタリングし、共通ヘルパーを `source` してテストロジックのみに絞り込む（300 行以下に削減）

## Capabilities

### New Capabilities

- `tests/helpers/test-common.sh` が共通テストユーティリティとして再利用可能になる（他テストスクリプトからも `source` 可能）

### Modified Capabilities

- `skillmd-pilot-fixes.test.sh` の行数が 300 行以下に収まり、ベースライン閾値警告が解消される

## Impact

- `plugins/twl/tests/helpers/test-common.sh`: 新規作成
- `plugins/twl/tests/scenarios/skillmd-pilot-fixes.test.sh`: ヘルパー関数をインライン定義から外部 source に変更
