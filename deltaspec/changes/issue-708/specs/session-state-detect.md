## MODIFIED Requirements

### Requirement: esc-to-interrupt → processing

`detect_state()` は `"esc to interrupt"` のみが表示されている場合、`processing` を返さなければならない（SHALL）。

#### Scenario: esc to interrupt のみ表示時に processing を返す
- **WHEN** tmux capture-pane 最終行に `"esc to interrupt"` が含まれ、`"bypass permissions"` は含まれない
- **THEN** `detect_state()` は `processing` を返す

#### Scenario: esc to interrupt + Thinking 表示時に processing を返す
- **WHEN** tmux capture-pane に `"esc to interrupt"` と `"Thinking"` が含まれ、`"bypass permissions"` は含まれない
- **THEN** `detect_state()` は `processing` を返す

### Requirement: bypass-permissions → input-waiting

`detect_state()` は `"bypass permissions"` が表示されている場合、`input-waiting` を返さなければならない（SHALL）。`"esc to interrupt"` の有無に関わらず `"bypass permissions"` が優先される。

#### Scenario: bypass permissions のみ表示時に input-waiting を返す
- **WHEN** tmux capture-pane 最終行に `"bypass permissions"` が含まれ、`"esc to interrupt"` は含まれない
- **THEN** `detect_state()` は `input-waiting` を返す

#### Scenario: bypass permissions + esc to interrupt 同時表示時に input-waiting を返す
- **WHEN** tmux capture-pane 最終行に `"bypass permissions"` と `"esc to interrupt"` の両方が含まれる
- **THEN** `detect_state()` は `input-waiting` を返す（bypass 優先）

### Requirement: テストカバレッジ

`session-state-input-waiting.bats` は上記シナリオを検証する 4 件のテストを含まなければならない（MUST）。既存 12 件のテストは引き続き PASS しなければならない（MUST）。

#### Scenario: 既存テスト継続 PASS
- **WHEN** `session-state-input-waiting.bats` の全テストを実行する
- **THEN** 16 件すべてが PASS する
