## ADDED Requirements

### Requirement: SESSION_ID サニタイズ（SU-9）

supervisor hook 5 本（heartbeat, input-wait, input-clear, skill-step, session-end）は SESSION_ID をファイル名に埋め込む直前に allow-list サニタイズ（`[A-Za-z0-9_-]`）を適用しなければならない（SHALL）。

サニタイズ後に SESSION_ID が空文字となった場合は `$$`（プロセス ID）にフォールバックしなければならない（SHALL）。

#### Scenario: path-traversal 文字を含む SESSION_ID

- **WHEN** SESSION_ID が `../../etc/passwd` のような path-traversal 文字を含む値で hook が呼び出される
- **THEN** SESSION_ID はサニタイズされ、安全なファイル名部分のみが使用されなければならない（MUST）

#### Scenario: 通常の UUID 形式の SESSION_ID

- **WHEN** SESSION_ID が `550e8400-e29b-41d4-a716-446655440000` 形式の UUID で hook が呼び出される
- **THEN** UUID のハイフンは許可文字のため SESSION_ID はそのまま使用されなければならない（SHALL）

#### Scenario: SESSION_ID が空になった場合のフォールバック

- **WHEN** SESSION_ID がサニタイズ後に空文字になる
- **THEN** SESSION_ID には `$$`（プロセス ID）が使用されなければならない（SHALL）

### Requirement: サニタイズ警告出力

supervisor hook はサニタイズで SESSION_ID の値が変化した場合に限り、警告行を stderr に出力しなければならない（SHALL）。

警告行は raw SESSION_ID の値を含んではならない（MUST NOT）。

#### Scenario: サニタイズで値が変化した場合の警告

- **WHEN** SESSION_ID にサニタイズ対象文字が含まれ、サニタイズ後の値が元の値と異なる
- **THEN** `[supervisor-hook][warn] SESSION_ID sanitized (hook=<name> pid=<pid>)` が stderr に出力されなければならない（MUST）

#### Scenario: サニタイズで値が変化しない場合は警告なし

- **WHEN** SESSION_ID が allow-list 文字のみで構成される
- **THEN** stderr に何も出力されてはならない（MUST NOT）
