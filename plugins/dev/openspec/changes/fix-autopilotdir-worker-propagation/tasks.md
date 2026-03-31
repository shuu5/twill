## 1. autopilot-phase-execute.md の修正

- [x] 1.1 `resolve_issue_repo_context()` の else 分岐で `PILOT_AUTOPILOT_DIR="$AUTOPILOT_DIR"` を `PILOT_AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"` に変更

## 2. autopilot-launch.md の修正

- [x] 2.1 `AUTOPILOT_ENV` 設定ロジックを修正: `PILOT_AUTOPILOT_DIR` が空の場合 `${PROJECT_DIR}/.autopilot` をフォールバックとして使用し、常に `AUTOPILOT_ENV` を設定する

## 3. 検証

- [x] 3.1 openspec scenario が specs の全シナリオを網羅していることを確認
