## Why

autopilot-launch.md は 6 ステップの bash コードブロックを Pilot LLM が毎回解釈・構築して実行する構造。特に tmux new-window コマンドは env + AUTOPILOT_DIR + cld + context-args + prompt を 1 行に結合し printf `%q` クォーティングが 5 箇所あるため、引数の脱落・クォートミスが非決定的に発生する。2026-04-01 セッションで Issue 番号が Worker に渡らないバグとして顕在化した。

## What Changes

- `scripts/autopilot-launch.sh` を新設し、Worker 起動の決定的ロジック（バリデーション、cld 解決、state-write、LAUNCH_DIR 計算、tmux 起動、クラッシュ検知フック）を委譲
- `commands/autopilot-launch.md` を簡素化し、コンテキスト構築（Step 4）のみ LLM が担当、残りは `bash $SCRIPTS_ROOT/autopilot-launch.sh` 呼び出しに置換
- deps.yaml の autopilot-launch calls に `script: autopilot-launch` を追加

## Capabilities

### New Capabilities

- `scripts/autopilot-launch.sh`: フラグ形式（`--issue N --project-dir DIR --autopilot-dir DIR [--context TEXT] [--repo-owner OWNER --repo-name NAME]`）で Worker を起動する決定的シェルスクリプト
- 入力バリデーション（ISSUE 数値チェック、パストラバーサル防止）をスクリプト内で実行
- bare repo 検出による LAUNCH_DIR 自動計算

### Modified Capabilities

- `commands/autopilot-launch.md`: Step 4（コンテキスト注入テキスト構築）のみ LLM 担当に簡素化
- deps.yaml: autopilot-launch の calls 定義に script 参照を追加

## Impact

- 影響ファイル: `scripts/autopilot-launch.sh`（新規）、`commands/autopilot-launch.md`（大幅簡素化）、`deps.yaml`（calls 更新）
- 依存: `scripts/cld-spawn`（参考実装）、`scripts/state-write.sh`、`scripts/crash-detect.sh`
- 既存の autopilot ワークフロー全体に影響（Worker 起動パスの変更）
