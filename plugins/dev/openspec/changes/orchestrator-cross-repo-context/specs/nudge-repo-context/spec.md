## MODIFIED Requirements

### Requirement: _nudge_command_for_pattern が entry を受け取る

`_nudge_command_for_pattern()` は第3引数として `entry` を受け取らなければならない（SHALL）。

#### Scenario: entry 引数の追加
- **WHEN** `_nudge_command_for_pattern "$pane_output" "$issue" "$entry"` が呼ばれる
- **THEN** 関数内で `resolve_issue_repo_context "$entry"` を呼び出して ISSUE_REPO_OWNER / ISSUE_REPO_NAME を設定する

### Requirement: クロスリポ環境での --repo フラグ付き gh 呼び出し

`_nudge_command_for_pattern()` は ISSUE_REPO_OWNER / ISSUE_REPO_NAME が設定されている場合、`gh issue view` に `--repo "$ISSUE_REPO_OWNER/$ISSUE_REPO_NAME"` を付与しなければならない（SHALL）。

#### Scenario: クロスリポ環境での is_quick 確認
- **WHEN** entry が "_default" 以外のリポを指し、状態ファイルに is_quick がない
- **THEN** `gh issue view "$issue" --repo "$ISSUE_REPO_OWNER/$ISSUE_REPO_NAME" --json labels ...` を実行する

#### Scenario: デフォルトリポでの is_quick 確認（後方互換）
- **WHEN** entry が "_default" （ISSUE_REPO_OWNER が空）
- **THEN** `gh issue view "$issue" --json labels ...` を従来通り実行する（--repo フラグなし）

### Requirement: check_and_nudge が entry を受け取り伝搬する

`check_and_nudge()` は第3引数として `entry` を受け取り、`_nudge_command_for_pattern()` 呼び出し時に渡さなければならない（SHALL）。

#### Scenario: check_and_nudge での entry 伝搬
- **WHEN** `check_and_nudge "$issue" "$window_name" "$entry"` が呼ばれる
- **THEN** `_nudge_command_for_pattern "$pane_output" "$issue" "$entry"` を呼び出す

### Requirement: poll_single が entry を受け取る

`poll_single()` は entry を第1引数として受け取り、内部で `resolve_issue_repo_context "$entry"` を呼び出して issue 番号を取得しなければならない（SHALL）。

#### Scenario: poll_single での entry 受け取り
- **WHEN** `poll_single "$entry"` が呼ばれる
- **THEN** `resolve_issue_repo_context "$entry"` を実行し `$ISSUE` から issue 番号を取得する

#### Scenario: check_and_nudge への entry 伝搬
- **WHEN** poll_single の running ケースで check_and_nudge を呼ぶ
- **THEN** `check_and_nudge "$issue" "$window_name" "$entry"` を呼び出す

### Requirement: poll_phase が entry リストを受け取る

`poll_phase()` は issue 番号リストではなく entry リストを受け取り、各 entry から issue 番号を抽出しなければならない（SHALL）。

#### Scenario: poll_phase での entry リスト受け取り
- **WHEN** `poll_phase "${BATCH[@]}"` が呼ばれる
- **THEN** 各 entry に対して `resolve_issue_repo_context "$entry"` で issue 番号を取得する

#### Scenario: check_and_nudge への entry 伝搬
- **WHEN** poll_phase の running ケースで check_and_nudge を呼ぶ
- **THEN** `check_and_nudge "$issue" "$window_name" "$entry"` を呼び出す
