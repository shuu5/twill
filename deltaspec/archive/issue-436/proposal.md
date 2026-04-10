## Why

`twl spec new` で生成される `.deltaspec.yaml` に `issue:` フィールドが含まれないため、`autopilot-orchestrator.sh` の `_archive_deltaspec_changes_for_issue()` が grep で 0 件ヒットし、DeltaSpec change が正しく archive されない。

## What Changes

- `cli/twl/src/twl/spec/new.py`: name が `issue-\d+` パターンにマッチする場合、`.deltaspec.yaml` に `issue: <N>` フィールドを自動追加
- `plugins/twl/scripts/autopilot-orchestrator.sh`: `issue:` フィールドでの grep に加え、`name: issue-<N>` パターンでのフォールバック検索を追加
- `cli/twl/src/twl/autopilot/orchestrator.py`: Python 版 orchestrator にも同じフォールバック検索ロジックを追加
- `plugins/twl/commands/change-propose.md`: Step 0 の `.deltaspec.yaml` 補完処理に `issue:` フィールドも追加

## Capabilities

### New Capabilities

- `twl spec new "issue-<N>"` 実行時に `.deltaspec.yaml` へ `issue: <N>` が自動付与される

### Modified Capabilities

- orchestrator の archive フローが `issue:` フィールドと `name: issue-<N>` パターンの両方で change を検出できるようになる
- `change-propose` コマンドが `.deltaspec.yaml` 補完時に `issue:` フィールドを追加する

## Impact

- **影響ファイル**: `cli/twl/src/twl/spec/new.py`, `plugins/twl/scripts/autopilot-orchestrator.sh`, `cli/twl/src/twl/autopilot/orchestrator.py`, `plugins/twl/commands/change-propose.md`
- **後方互換性**: フォールバック追加により既存の `.deltaspec.yaml`（`issue:` なし）も引き続き検出可能
- **テスト**: spec/new の unit test、orchestrator の archive フロー integration test
