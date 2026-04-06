## Why

co-autopilot の Pilot セッションと Worker セッションが異なる `.autopilot/` ディレクトリを参照し、状態ファイル（issue-{N}.json, session.json）が分断される。PROJECT_DIR の導出方法が3箇所で異なり、co-autopilot SKILL.md が `AUTOPILOT_DIR` を export していないことが根本原因。

## What Changes

- co-autopilot SKILL.md の Step 0 で `AUTOPILOT_DIR` を明示的に export
- autopilot-init.md の全スクリプト呼び出しで `AUTOPILOT_DIR` 環境変数を伝搬
- autopilot-phase-execute.md の全スクリプト呼び出しで `AUTOPILOT_DIR` 環境変数を伝搬

## Capabilities

### New Capabilities

- なし（既存機能のバグ修正）

### Modified Capabilities

- Pilot/Worker 間で統一された `.autopilot/` パスを使用
- bare repo 構成での autopilot 状態管理が正常に動作

## Impact

- **影響ファイル**: `skills/co-autopilot/SKILL.md`, `commands/autopilot-init.md`, `commands/autopilot-phase-execute.md`
- **影響なし**: `scripts/*.sh`（既に `${AUTOPILOT_DIR:-default}` パターンで env override 対応済み）
- **依存関係**: なし（#70 とは独立）
