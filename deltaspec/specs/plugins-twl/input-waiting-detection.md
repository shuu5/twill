## Requirements

### Requirement: detect_input_waiting 関数が input-waiting パターンを検知しなければならない

`autopilot-orchestrator.sh` に `detect_input_waiting(pane_output)` 関数を追加し、Menu UI パターン 3 種以上 + Free-form text パターン 3 種以上を検知しなければならない（SHALL）。検知した pattern name を返し、未検知時は空文字を返す。

#### Scenario: Menu UI パターンを検知する
- **WHEN** pane_output に `Enter to select`、`↑/↓ to navigate`、または `❯ <数字>.` を含む行があるとき
- **THEN** `detect_input_waiting` は該当 pattern name を返す

#### Scenario: Free-form text パターンを検知する
- **WHEN** pane_output に `よろしいですか[？?]`、`続けますか`、`進んでよいですか`、または `[y/N]` を含む行があるとき
- **THEN** `detect_input_waiting` は該当 pattern name を返す

#### Scenario: Wave 7 #470 再現パターンを検知する
- **WHEN** pane_output に「このまま実装に進んでよいですか？」を含むとき
- **THEN** `detect_input_waiting` は free-form pattern name を返す

#### Scenario: chain 進捗キーワードのみでは false trigger しない
- **WHEN** pane_output が `setup chain 完了` や `>>> 提案完了` などの chain 進捗キーワードのみを含むとき
- **THEN** `detect_input_waiting` は空文字を返す

### Requirement: check_and_nudge が capture-pane を -S -30 で取得しなければならない

`check_and_nudge()` の `tmux capture-pane` オプションを `-S -5` から `-S -30` に変更し、同一 pane_output を `detect_input_waiting` と `_nudge_command_for_pattern` の両方で再利用しなければならない（SHALL）。

#### Scenario: detect_input_waiting と chain-stop 判定で同一 pane_output を使用する
- **WHEN** `check_and_nudge()` が実行されるとき
- **THEN** `detect_input_waiting` は `_nudge_command_for_pattern` と同じ pane_output 変数を参照する（新規 capture-pane 呼び出しなし）

### Requirement: detect_input_waiting は chain-stop 判定前に呼ばれなければならない

`check_and_nudge()` 内で `_nudge_command_for_pattern()` による chain-stop 判定を実行する前に `detect_input_waiting()` を呼び出さなければならない（SHALL）。input-waiting 検知時も nudge/inject は抑止しない。

#### Scenario: input-waiting と chain-stop が同時成立しても干渉しない
- **WHEN** pane_output が input-waiting パターンと chain-stop 終端を同時に含むとき
- **THEN** `detect_input_waiting` が先に state 書き込みを行い、その後 `_nudge_command_for_pattern` が chain-stop として nudge を実行する

### Requirement: デバウンスにより連続 2 poll cycle 検知で state 書き込みを確定しなければならない

同一 issue で同一 pattern を連続 2 poll cycle 検知した場合のみ state write を実行しなければならない（SHALL）。1 回目は warn ログのみ出力し state 書き込みをスキップする。

#### Scenario: 1 回目検知では state 書き込みをスキップする
- **WHEN** `detect_input_waiting` が初めて同一 issue + 同一 pattern を検知したとき
- **THEN** warn ログを出力し、state.py の write は実行しない

#### Scenario: 2 回目検知で state 書き込みを確定する
- **WHEN** 前の poll cycle と同じ issue + pattern を再度検知したとき
- **THEN** `python3 -m twl.autopilot.state write --role pilot --set input_waiting_detected=<pattern> --set input_waiting_at=<ts>` を実行し trace log に追記する

### Requirement: 検知イベントを trace log に追記しなければならない

state 書き込みが確定したとき、`${AUTOPILOT_DIR}/trace/input-waiting-YYYYMMDD.log` に `[ts] issue=N pattern=<name> window=<w>` 形式で追記しなければならない（SHALL）。

#### Scenario: trace log が存在しない場合は新規作成する
- **WHEN** 当日の trace log ファイルが存在しないとき
- **THEN** ファイルを新規作成してイベントを追記する
