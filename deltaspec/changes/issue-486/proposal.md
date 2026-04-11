## Why

Wave 6 実行中に co-autopilot Pilot が `Enter to select` 形式の approval UI で停止したが、`session-state.sh` の `detect_state()` が末尾1行のみをスキャンするため approval UI を `processing` と誤判定し、90秒間検知できなかった。さらに su-observer の Monitor 定義に `input-waiting` / `pilot-idle` / `stagnate` 等の標準チャネルが存在しないため、構造的な早期検知ができない状態が続いている。

## What Changes

- `plugins/session/scripts/session-state.sh`: `detect_state()` の末尾1行マッチを廃止し、`tail -5` 全体に対して approval UI / AskUserQuestion / y/N パターンをスキャン
- `plugins/session/tests/`: approval UI パターン 3 種以上を検証する bats テストを追加
- `plugins/twl/skills/su-observer/refs/monitor-channel-catalog.md`: 新規作成（`refs/` ディレクトリも新規）。INPUT-WAIT / PILOT-IDLE / STAGNATE / WORKERS / PHASE-DONE / NON-TERMINAL の 6 チャネルを bash スニペット付きで定義
- `plugins/twl/skills/su-observer/SKILL.md`: Step 0 および Step 1 に monitor-channel-catalog 参照ステップを追記
- `plugins/twl/refs/observation-pattern-catalog.md`: INPUT-WAIT / PILOT-IDLE / STAGNATE パターンを追記
- `plugins/twl/commands/problem-detect.md`: 新チャネルを検知対象に追加
- `plugins/twl/deps.yaml`: `su-observer` エントリの `calls:` に `- reference: monitor-channel-catalog` を追記

## Capabilities

### New Capabilities

- **approval UI input-waiting 判定**: `session-state.sh detect_state` が `Enter to select · ↑/↓ to navigate`、`承認しますか？`、`Do you want to`、`[y/N]`、`Waiting for user input` 等のパターンを `tail -5` 全体スキャンで捕捉し `input-waiting` を返す
- **Monitor 標準チャネルカタログ**: `refs/monitor-channel-catalog.md` に 6 チャネル（INPUT-WAIT / PILOT-IDLE / STAGNATE / WORKERS / PHASE-DONE / NON-TERMINAL）の定義・bash スニペット・閾値を提供。su-observer が Wave 開始時に参照して Monitor tool を起動できる
- **STAGNATE 監視パス明示**: `.supervisor/working-memory.md`、`.autopilot/waves/<N>.summary.md`、`.autopilot/checkpoints/*.json` の mtime を 10 分閾値で評価するスニペットを提供

### Modified Capabilities

- **su-observer Wave 監視フロー**: SKILL.md Step 0 にカタログ読み込み、Step 1 Wave 管理パスに Monitor 起動ステップ（3.5）を追加
- **observation-pattern-catalog**: INPUT-WAIT / PILOT-IDLE / STAGNATE の problem pattern と介入層（Auto/Confirm/Escalate）を追記
- **problem-detect**: 新 3 チャネルを検知対象に組み込み

## Impact

- `plugins/session/scripts/session-state.sh`（detect_state ロジック変更）
- `plugins/session/tests/`（bats テスト追加）
- `plugins/twl/skills/su-observer/SKILL.md`（Step 0 / Step 1 更新）
- `plugins/twl/skills/su-observer/refs/monitor-channel-catalog.md`（新規）
- `plugins/twl/refs/observation-pattern-catalog.md`（パターン追記）
- `plugins/twl/commands/problem-detect.md`（チャネル追加）
- `plugins/twl/deps.yaml`（reference 追記）
