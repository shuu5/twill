## Why

`autopilot-orchestrator.sh` の `check_and_nudge()` は tmux 出力を監視しているが、input-waiting（質問・選択 UI）の検知パターンが未定義のため、Worker が自由テキスト質問や選択肢 UI で停止しても Pilot が誤認識し、外部介入まで 3 分以上停滞する問題が Wave 7 で観測された（Issue #510）。

## What Changes

- `plugins/twl/scripts/autopilot-orchestrator.sh`: 新関数 `detect_input_waiting()` を追加し、Menu UI 3 種以上 + Free-form text 3 種以上のパターンを検知する
- `check_and_nudge()` の `capture-pane` を `-S -5` から `-S -30` に変更し、`detect_input_waiting` と `_nudge_command_for_pattern` 両方で同一 pane_output を再利用する
- `check_and_nudge()` 内で chain-stop 判定前に `detect_input_waiting()` を呼び、input-waiting 検知時に state 書き込みを行う（nudge/inject は抑止しない）
- `cli/twl/src/twl/autopilot/state.py`: `_init_issue()` と `_PILOT_ISSUE_ALLOWED_KEYS` に `input_waiting_detected`, `input_waiting_at` を追加
- `plugins/twl/skills/co-autopilot/SKILL.md`: Step 4 に「2.5 Input-waiting 確認」と Silence heartbeat 節を追加
- `plugins/twl/tests/bats/scripts/autopilot-orchestrator.bats`: 新 fixture ≥9 test case 追加

## Capabilities

### New Capabilities

- `detect_input_waiting()`: tmux pane_output から入力待ち状態を検知し、state file に `input_waiting_detected` / `input_waiting_at` を書き込む
- デバウンス機構: 同一 issue で同一 pattern を連続 2 poll cycle 検知した場合のみ state 書き込みを確定（誤検知抑制）
- Trace log: `${AUTOPILOT_DIR}/trace/input-waiting-*.log` へのイベント追記
- Pilot Silence heartbeat: 全 worker の `updated_at` が 5 分以上無変化時に Pilot LLM が手動で input-waiting を検査し、未解消なら su-observer にエスカレーション

### Modified Capabilities

- `check_and_nudge()`: `capture-pane` 末尾 5 行 → 30 行に拡張し、`detect_input_waiting` を chain-stop 判定前に呼び出す
- `co-autopilot/SKILL.md` Step 4: 閾値別アクション（<5 分=warn、≥5 分=inject、≥10 分=escalate）を追加

## Impact

- **影響ファイル**: `plugins/twl/scripts/autopilot-orchestrator.sh`, `cli/twl/src/twl/autopilot/state.py`, `plugins/twl/skills/co-autopilot/SKILL.md`
- **テスト追加**: `plugins/twl/tests/bats/scripts/autopilot-orchestrator.bats`（≥9 test case）
- **スキーマ変更**: `state.py` の allowed_keys 追加のみ。既存 state file 後方互換を維持（migration 不要）
- **スコープ外**: `_nudge_command_for_pattern` のパターン変更、`deps.yaml` の変更、`worker-terminal-guard.sh` の変更
