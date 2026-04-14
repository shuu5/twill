## ADDED Requirements

### Requirement: co-autopilot/SKILL.md Step 4 に Input-waiting 確認手順（2.5）を挿入しなければならない

`plugins/twl/skills/co-autopilot/SKILL.md` の Step 4「2. 未完了の場合 — Worker 状態確認」の直後、「3. Stagnation 検知時」の前に手順 2.5 を挿入しなければならない（SHALL）。閾値別アクション（<5 分=warn、≥5 分=inject、≥10 分=escalate）を明記する。

#### Scenario: Input-waiting 検知時に閾値別アクションを実行する
- **WHEN** Pilot が Worker の state file を読み `input_waiting_detected` が非空であるとき
- **THEN** `input_waiting_at` から経過時間を計算し: <5 分は warn ログのみ、≥5 分は session-comm.sh inject-file で確認メッセージ送信、≥10 分は state に `escalation_requested=input_waiting_stall` を書き込む

#### Scenario: input_waiting_detected が null/空の場合はスキップする
- **WHEN** Pilot が Worker の state file を読み `input_waiting_detected` が null または空文字であるとき
- **THEN** 手順 2.5 の処理をスキップし次の手順へ進む

### Requirement: co-autopilot/SKILL.md Step 4 末尾に Silence heartbeat 節を追加しなければならない

全 worker の `updated_at` が 5 分以上無変化で PHASE_COMPLETE 未検知の場合、Pilot LLM が tmux pane を直接確認し input-waiting を手動検査しなければならない（SHALL）。これは orchestrator が停止している可能性への補完である。

#### Scenario: 全 worker が 5 分以上沈黙している場合に Pilot が pane を確認する
- **WHEN** 全 worker の `updated_at` が 5 分以上更新されておらず PHASE_COMPLETE が未検知であるとき
- **THEN** Pilot は全 worker window に対して `tmux capture-pane -t <window> -p -S -30` を実行し、取得した pane_output に input-waiting regex を手動適用する

#### Scenario: input-waiting が未検知でも沈黙継続時は su-observer にエスカレーションする
- **WHEN** Silence heartbeat で input-waiting が検知されず、沈黙が継続するとき
- **THEN** su-observer escalate（state に escalation を書き込み、su-observer の Monitor 介入を期待する）

#### Scenario: 閾値 5 分は AUTOPILOT_STAGNATE_SEC（10 分）の半分である
- **WHEN** Silence heartbeat の閾値を設定するとき
- **THEN** 5 分（300 秒）を使用する。これは `AUTOPILOT_STAGNATE_SEC` デフォルト 600 秒の半分であり、input-waiting は stagnation より早く検知したいため

### Requirement: bats テストが detection パターン全種を検証しなければならない

`plugins/twl/tests/bats/scripts/autopilot-orchestrator.bats` に ≥9 test case を追加しなければならない（SHALL）: Menu UI fixture 3 種 + Free-form text fixture 3 種 + Wave 7 #470 再現 fixture + デバウンス 2 回検証 + false positive 非検知 1 fixture。

#### Scenario: Menu UI fixture 3 種が検知される
- **WHEN** `Enter to select`、`↑/↓ to navigate`、`❯ 1.` を含む pane_output に対して `detect_input_waiting` を実行するとき
- **THEN** それぞれ非空の pattern name が返る（3 test case）

#### Scenario: Free-form text fixture 3 種が検知される
- **WHEN** 「よろしいですか？」「続けますか？」「[y/N]」を含む pane_output に対して `detect_input_waiting` を実行するとき
- **THEN** それぞれ非空の pattern name が返る（3 test case）

#### Scenario: デバウンスが 2 poll cycle で state write を確定する
- **WHEN** 同一 issue + 同一 pattern を 1 回目検知した場合は state write がスキップされ、2 回目検知で state write が実行されるとき
- **THEN** `state read --field input_waiting_detected` が 1 回目は空、2 回目に pattern name を返す（2 test case）

#### Scenario: chain 進捗キーワードのみで false positive しない
- **WHEN** chain 進捗キーワードのみを含む pane_output に対して `detect_input_waiting` を実行するとき
- **THEN** 空文字が返る（1 test case）
