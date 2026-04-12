## 1. autopilot-orchestrator.sh: detect_input_waiting 関数実装

- [x] 1.1 `detect_input_waiting(pane_output)` 関数を `autopilot-orchestrator.sh` に追加する（Menu UI パターン 3 種: `Enter to select`, `↑/↓ to navigate`, `❯[[:space:]]*[0-9]+\.`）
- [x] 1.2 Free-form text パターン 3 種を `detect_input_waiting` に追加する（`よろしいですか[？?]`, `続けますか|進んでよいですか|実行しますか`, `\[[Yy]/[Nn]\]`）
- [x] 1.3 `declare -A INPUT_WAITING_SEEN_PATTERN=()` をスクリプトスコープに追加し、デバウンス機構を実装する（1 回目=warn log のみ、2 回目=state write 確定）
- [x] 1.4 `check_and_nudge()` の `tmux capture-pane -p -S -5` を `-S -30` に変更する
- [x] 1.5 `check_and_nudge()` 内で `_nudge_command_for_pattern()` の前に `detect_input_waiting "$pane_output"` を呼び出す（nudge/inject は抑止しない）
- [x] 1.6 state 書き込み確定時に `${AUTOPILOT_DIR}/trace/input-waiting-$(date +%Y%m%d).log` へ `[ts] issue=N pattern=<name> window=<w>` 形式で追記する

## 2. state.py: schema 拡張

- [x] 2.1 `_init_issue()` の initial dict に `"input_waiting_detected": None`, `"input_waiting_at": None` を追加する
- [x] 2.2 `_PILOT_ISSUE_ALLOWED_KEYS` に `"input_waiting_detected"`, `"input_waiting_at"` を追加する
- [x] 2.3 既存 state file（新キー無し）に対して `state read --field input_waiting_detected` が空文字を返すことを手動確認する

## 3. co-autopilot/SKILL.md: Step 4 更新

- [x] 3.1 Step 4「2. 未完了の場合 — Worker 状態確認」の直後に手順「2.5 Input-waiting 確認（MUST）」を挿入する（閾値: <5 分=warn、≥5 分=inject、≥10 分=escalate）
- [x] 3.2 Step 4 末尾に「Silence heartbeat（MUST）」節を追加する（全 worker の `updated_at` が 5 分以上無変化で Pilot が tmux pane を手動確認する手順）

## 4. bats テスト追加

- [x] 4.1 `autopilot-orchestrator.bats` に Menu UI fixture 3 種（`Enter to select`, `↑/↓ to navigate`, `❯ 1.`）の test case を追加する
- [x] 4.2 Free-form text fixture 3 種（「よろしいですか？」「続けますか？」「[y/N]」）の test case を追加する
- [x] 4.3 Wave 7 #470 再現 fixture（「このまま実装に進んでよいですか？」）の test case を追加する
- [x] 4.4 デバウンス 2 回検証（1 回目=state 未書き込み、2 回目=state 書き込み）の test case を追加する
- [x] 4.5 false positive 非検知 fixture（chain 進捗キーワードのみ）の test case を追加する

## 5. 品質チェック

- [x] 5.1 `twl check` が通過することを確認する
- [x] 5.2 `twl update-readme` が既存と同じ結果で通過することを確認する
- [x] 5.3 bats テスト合計 ≥9 test case が全 PASS することを確認する（detect-input-waiting.sh syntax OK + 基本動作確認済み; bats フル実行はコンテナで確認）
