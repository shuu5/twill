## 1. 修正

- [x] 1.1 `commands/autopilot-phase-execute.md` の `resolve_issue_repo_context()` で `else` ブランチの `PILOT_AUTOPILOT_DIR=""` を `PILOT_AUTOPILOT_DIR="$AUTOPILOT_DIR"` に変更

## 2. 検証

- [x] 2.1 既存テスト（autopilot-launch-input-validation）が pass することを確認
