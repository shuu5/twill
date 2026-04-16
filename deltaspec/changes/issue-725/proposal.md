## Why

全 5 supervisor hook が `AUTOPILOT_DIR` 環境変数の存在をゲート条件としているため、co-explore / co-issue 等の非 autopilot セッションでは `AUTOPILOT_DIR` が未設定となり、イベントファイルが `.supervisor/events/` に書き出されない。これにより observer は session-state.sh polling にフォールバックし、false positive (#708/#722) が発生する。

## What Changes

- 全 5 supervisor hook の EVENTS_DIR 解決を `AUTOPILOT_DIR` ベースから `git rev-parse --git-common-dir` ベースに変更
- `AUTOPILOT_DIR` ゲート（未設定時の早期 exit）を撤去
- `git rev-parse --git-common-dir` の成功を唯一のゲート条件とする（git 外セッションでは exit 0）
- EVENTS_DIR を `${GIT_COMMON_DIR}/../main/.supervisor/events` として解決
- 既存テスト `_no_autopilot_dir` 群を「AUTOPILOT_DIR 未設定 + git 内 → イベント生成」に更新

## Capabilities

### New Capabilities

- 非 autopilot セッション（co-explore / co-issue / co-architect 等）での supervisor イベント発火
- AUTOPILOT_DIR 未設定の cld-spawn セッションからも AskUserQuestion / heartbeat 等のイベントを observer が検知可能

### Modified Capabilities

- supervisor hook の EVENTS_DIR 解決ロジック: `AUTOPILOT_DIR`-relative → `git rev-parse --git-common-dir`-relative
- autopilot Worker セッション（AUTOPILOT_DIR 設定済み）でも EVENTS_DIR が `main/.supervisor/events` を指すことは変わらない（後方互換）

## Impact

**変更ファイル:**
- `plugins/twl/scripts/hooks/supervisor-input-wait.sh`
- `plugins/twl/scripts/hooks/supervisor-input-clear.sh`
- `plugins/twl/scripts/hooks/supervisor-heartbeat.sh`
- `plugins/twl/scripts/hooks/supervisor-skill-step.sh`
- `plugins/twl/scripts/hooks/supervisor-session-end.sh`

**関連テスト:**
- `_no_autopilot_dir` 群のテストケース更新が必要

**依存関係:**
- bare repo 構造（`.bare/` + `main/` + `worktrees/`）を前提とした EVENTS_DIR パス解決
- `git rev-parse --git-common-dir` が使用可能な git 環境
