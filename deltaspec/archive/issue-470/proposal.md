## Why

Pilot が `AUTOPILOT_DIR` 未設定のまま実行すると `_autopilot_dir()` が main worktree 配下（`twill/main/.autopilot/`）を返すが、実際の state file は bare sibling（`twill/.autopilot/`）にある。また `_PILOT_ISSUE_ALLOWED_KEYS` に `pr` が含まれないため、Worker が `pr` を書き残さなかった場合の Pilot による recovery が不能になる。

## What Changes

- `cli/twl/src/twl/autopilot/state.py`: `_autopilot_dir()` の fallback に bare sibling 探索ロジックを追加（main worktree path から `../` を試す）
- `cli/twl/src/twl/autopilot/state.py`: `_PILOT_ISSUE_ALLOWED_KEYS` に `pr` を追加（1 行変更）
- `cli/twl/src/twl/autopilot/state.py`: `_autopilot_dir()` のエラーメッセージ改善（試したパス一覧 + `AUTOPILOT_DIR` export 推奨）
- `plugins/twl/scripts/autopilot-orchestrator.sh`: `AUTOPILOT_DIR` の export 必須化、未設定時 warning
- `plugins/twl/skills/co-autopilot/SKILL.md`: `AUTOPILOT_DIR` export 前提を明示
- `cli/twl/tests/autopilot/test_state.py`: bare sibling + main worktree 両配置パターンのテスト追加

## Capabilities

### New Capabilities

- **bare sibling 自動解決**: `_autopilot_dir()` が main worktree path から `../` を確認し bare sibling の `.autopilot/` を優先的に返す（`twill/main/../.autopilot` = `twill/.autopilot`）
- **Pilot `pr` 書き込み**: Emergency Bypass や recovery フローで Pilot が issue-{N}.json の `pr` フィールドを更新可能になる

### Modified Capabilities

- **`_autopilot_dir()` fallback 順序**: env var → main worktree 配下 → bare sibling → first real worktree → cwd の順に変更
- **エラーメッセージ**: ファイル不在時に試したパス一覧と `AUTOPILOT_DIR` export 手順を併記

## Impact

- 対象モジュール: `cli/twl/src/twl/autopilot/state.py`（RBAC + パス解決）
- 対象スクリプト: `plugins/twl/scripts/autopilot-orchestrator.sh`
- 対象ドキュメント: `plugins/twl/skills/co-autopilot/SKILL.md`
- 既存の `AUTOPILOT_DIR` 設定済み環境には影響なし（env var が最優先）
- Wave 4 以降の Pilot recovery フローが安定化する
