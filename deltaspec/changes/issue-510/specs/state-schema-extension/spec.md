## MODIFIED Requirements

### Requirement: _init_issue が input_waiting フィールドを初期化しなければならない

`cli/twl/src/twl/autopilot/state.py` の `_init_issue()` は `"input_waiting_detected": None` と `"input_waiting_at": None` を initial dict に含めなければならない（SHALL）。

#### Scenario: 新規 issue state file に input_waiting フィールドが含まれる
- **WHEN** 新規 issue state file が作成されるとき
- **THEN** `jq '.input_waiting_detected'` と `jq '.input_waiting_at'` が `null` を返す

#### Scenario: 既存 state file（新キー無し）で state read が空文字を返す
- **WHEN** `input_waiting_detected` キーが存在しない既存 state file に対して `state read --field input_waiting_detected` を実行するとき
- **THEN** 空文字（またはエラーなし終了）を返す

### Requirement: _PILOT_ISSUE_ALLOWED_KEYS が input_waiting フィールドを許可しなければならない

`_PILOT_ISSUE_ALLOWED_KEYS` に `"input_waiting_detected"` と `"input_waiting_at"` を追加し、`role=pilot` での書き込みを許可しなければならない（SHALL）。

#### Scenario: role=pilot で input_waiting_detected を書き込める
- **WHEN** `python3 -m twl.autopilot.state write --role pilot --set "input_waiting_detected=menu_enter_select"` を実行するとき
- **THEN** state file の `input_waiting_detected` が `"menu_enter_select"` に更新される

#### Scenario: _validate_role と _check_pilot_identity は改修しない
- **WHEN** `role=pilot` で既存の書き込み検証が実行されるとき
- **THEN** `_validate_role` と `_check_pilot_identity` の挙動は変化しない

### Requirement: orchestrator からの書き込みは role=pilot として実行されなければならない

`autopilot-orchestrator.sh` から state write を呼ぶ際は `--role pilot` を使用しなければならない（SHALL）。`role=orchestrator` を新設してはならない。

#### Scenario: orchestrator からの state write が成功する
- **WHEN** orchestrator が main worktree から `python3 -m twl.autopilot.state write --role pilot --set "input_waiting_detected=<pattern>"` を実行するとき
- **THEN** `_check_pilot_identity` を通過して state file が更新される
