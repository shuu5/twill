## MODIFIED Requirements

### Requirement: crash-detect 5状態検出

crash-detect.sh は session-state.sh を利用して Worker の 5 状態（idle/input-waiting/processing/error/exited）を検出しなければならない（SHALL）。exited および error 状態を crash として扱い、exit code 2 で終了しなければならない（MUST）。

#### Scenario: session-state.sh で exited 状態を検出
- **WHEN** session-state.sh が利用可能で、`session-state.sh state <window>` が `exited` を返す
- **THEN** crash-detect.sh は status を `failed` に遷移し、failure JSON に `detected_state: "exited"` を含め、exit code 2 で終了する

#### Scenario: session-state.sh で error 状態を検出
- **WHEN** session-state.sh が利用可能で、`session-state.sh state <window>` が `error` を返す
- **THEN** crash-detect.sh は status を `failed` に遷移し、failure JSON に `detected_state: "error"` を含め、exit code 2 で終了する

#### Scenario: session-state.sh で processing 状態を検出
- **WHEN** session-state.sh が利用可能で、`session-state.sh state <window>` が `processing` を返す
- **THEN** crash-detect.sh は exit code 0 で正常終了する

#### Scenario: session-state.sh で idle 状態を検出
- **WHEN** session-state.sh が利用可能で、`session-state.sh state <window>` が `idle` を返す
- **THEN** crash-detect.sh は exit code 0 で正常終了する

#### Scenario: session-state.sh で input-waiting 状態を検出
- **WHEN** session-state.sh が利用可能で、`session-state.sh state <window>` が `input-waiting` を返す
- **THEN** crash-detect.sh は exit code 0 で正常終了する

### Requirement: crash-detect フォールバック

session-state.sh が存在しないまたは実行不可の場合、crash-detect.sh は既存の tmux list-panes ベースの検知にフォールバックしなければならない（MUST）。エラー終了してはならない（MUST NOT）。

#### Scenario: session-state.sh 非存在時のフォールバック
- **WHEN** `SESSION_STATE_CMD` で指定されたパスに session-state.sh が存在しない
- **THEN** tmux list-panes による従来のペイン存在チェックで crash 検知を行い、正常に動作する

#### Scenario: session-state.sh が実行失敗した場合
- **WHEN** session-state.sh の実行がエラーを返す（window not found 等）
- **THEN** tmux list-panes フォールバックに切り替えて検知を継続する

### Requirement: crash-detect 既存インターフェース互換

crash-detect.sh の CLI インターフェース（`--issue N --window <window-name>`）と exit code 体系（0=正常, 1=エラー, 2=crash）は維持しなければならない（SHALL）。

#### Scenario: 既存引数形式の維持
- **WHEN** `crash-detect.sh --issue 1 --window "ap-#1"` を実行する
- **THEN** 従来と同じ引数形式で動作し、exit code 体系が維持される

### Requirement: crash-detect failure 情報の拡張

crash 検知時の failure JSON に `detected_state` フィールドを含めなければならない（SHALL）。session-state.sh 経由の場合は検出された状態名、フォールバック経由の場合は `"pane_absent"` を設定する。

#### Scenario: session-state.sh 経由の failure 情報
- **WHEN** session-state.sh で error 状態が検出されて crash と判定される
- **THEN** failure JSON に `"detected_state": "error"` が含まれる

#### Scenario: フォールバック経由の failure 情報
- **WHEN** tmux list-panes フォールバックでペイン消失が検出される
- **THEN** failure JSON に `"detected_state": "pane_absent"` が含まれる
