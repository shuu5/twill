## Why

`commands/autopilot-phase-execute.md` の `resolve_issue_repo_context()` で、単一リポジトリ（`repo_id == '_default'`）の場合に `PILOT_AUTOPILOT_DIR` が空文字列に設定される。autopilot-launch が Worker を起動する際、この空値が AUTOPILOT_DIR として渡され、Worker が状態ファイルを正しい場所に書けなくなる可能性がある。

## What Changes

- `resolve_issue_repo_context()` の `else` ブランチで `PILOT_AUTOPILOT_DIR="$AUTOPILOT_DIR"` をデフォルト値として設定

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- 単一リポジトリ時にも `PILOT_AUTOPILOT_DIR` が有効な値を保持し、Worker への AUTOPILOT_DIR 伝播が正常に機能する

## Impact

- 影響ファイル: `commands/autopilot-phase-execute.md`（1行変更）
- 影響範囲: autopilot-launch 経由の Worker 起動時の環境変数設定
- 依存: なし（既存の `$AUTOPILOT_DIR` 変数を参照するのみ）
