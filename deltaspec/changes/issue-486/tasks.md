## 1. session-state.sh 修正

- [x] 1.1 `INPUT_WAITING_PATTERNS` 配列を `session-state.sh` に追加（`Enter to select` / `承認しますか` / `確認しますか` / `Do you want to` / `[y/N]` / `[Y/n]` / `Type something` / `Waiting for user input`）
- [x] 1.2 `detect_state()` の `PROMPT_PATTERN` 適用を `tail -1` から `last_lines` 全体スキャンに変更
- [x] 1.3 `detect_state()` に `INPUT_WAITING_PATTERNS` ループを追加（PROMPT_PATTERN 全体スキャンの後、bypass permissions フォールバックの前）

## 2. bats テスト追加

- [x] 2.1 `plugins/session/tests/` 配下に `session-state-input-waiting.bats` を新規作成
- [x] 2.2 `detect_state()` を tmux なしでテストするモック関数を実装
- [x] 2.3 `Enter to select` パターンで `input-waiting` が返ることを検証するテスト追加
- [x] 2.4 日本語 `承認しますか？` パターンで `input-waiting` が返ることを検証するテスト追加
- [x] 2.5 `[y/N]` パターンで `input-waiting` が返ることを検証するテスト追加
- [x] 2.6 `Thinking...` 表示で `processing` が返ること（誤検知なし）を検証するテスト追加

## 3. monitor-channel-catalog 新設

- [x] 3.1 `plugins/twl/skills/su-observer/refs/` ディレクトリを作成
- [x] 3.2 `refs/monitor-channel-catalog.md` を作成し INPUT-WAIT / PILOT-IDLE / STAGNATE / WORKERS / PHASE-DONE / NON-TERMINAL の 6 チャネルを bash スニペット付きで定義
- [x] 3.3 STAGNATE セクションに監視対象 path（`.supervisor/working-memory.md` / `.autopilot/waves/<N>.summary.md` / `.autopilot/checkpoints/*.json`）を明記

## 4. su-observer SKILL.md 更新

- [x] 4.1 SKILL.md Step 0 に `refs/monitor-channel-catalog.md` を Read する旨を追記
- [x] 4.2 SKILL.md Step 1 Wave 管理フローの手順 3 と 4 の間に Step 3.5（Monitor 起動）を挿入
- [x] 4.3 SKILL.md Step 1「既存セッションの状態確認」に Monitor スニペット実行結果を確認ソースとして追加
- [x] 4.4 SKILL.md Step 1「問題を検出した場合」にチャネル名と catalog 照合の旨を追記

## 5. observation-pattern-catalog / problem-detect 更新

- [x] 5.1 `plugins/twl/refs/observation-pattern-catalog.md` に INPUT-WAIT パターン（検知条件・介入層: Auto）を追記
- [x] 5.2 `observation-pattern-catalog.md` に PILOT-IDLE パターン（検知条件・介入層: Confirm）を追記
- [x] 5.3 `observation-pattern-catalog.md` に STAGNATE パターン（検知条件・介入層: Confirm）を追記
- [x] 5.4 `plugins/twl/commands/problem-detect.md` に INPUT-WAIT / PILOT-IDLE / STAGNATE チャネルを検知対象として追加

## 6. deps.yaml 更新と検証

- [x] 6.1 `plugins/twl/deps.yaml` の `su-observer` エントリの `calls:` に `- reference: monitor-channel-catalog` を追記
- [x] 6.2 `twl check` を実行してエラーがないことを確認
- [x] 6.3 `twl update-readme` を実行
