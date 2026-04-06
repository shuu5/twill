## 1. orchestrator 修正

- [x] 1.1 `scripts/autopilot-orchestrator.sh` の `_nudge_command_for_pattern` 冒頭に `is_quick` 判定を追加（`state-read.sh` 一次取得 → gh API fallback）
- [x] 1.2 `is_quick=true` の場合、"setup chain 完了" および "workflow-test-ready.*で次に進めます" パターンで `return 1` を返す

## 2. テスト追加

- [x] 2.1 `tests/bats/scripts/orchestrator-nudge.bats` の `nudge-dispatch.sh` test double に `is_quick` 判定ロジックを追加（state ファイル stub 経由）
- [x] 2.2 quick Issue で "setup chain 完了" → nudge しないシナリオのテストを追加
- [x] 2.3 quick Issue で "workflow-test-ready で次に進めます" → nudge しないシナリオのテストを追加
- [x] 2.4 通常 Issue（`is_quick=false`）での既存シナリオが引き続きパスすることを確認
