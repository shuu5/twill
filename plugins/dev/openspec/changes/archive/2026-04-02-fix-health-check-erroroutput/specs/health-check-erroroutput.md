## MODIFIED Requirements

### Requirement: 多行エラー出力の1行正規化

`check_error_output` 関数は、複数行のエラー出力を1行に正規化しなければならない（SHALL）。結果集約ループの `pattern:detail` パース形式を維持するため、改行をセミコロンに変換する。

#### Scenario: 複数行エラー出力時のパース維持
- **WHEN** tmux capture-pane の出力に複数行のエラーメッセージが含まれる
- **THEN** `check_error_output` は `error_output:line1; line2; ...` の形式で1行のみ出力しなければならない（MUST）

#### Scenario: 単一行エラー出力時の動作維持
- **WHEN** エラーが1行のみの場合
- **THEN** 既存の `error_output:detail` 形式がそのまま維持されなければならない（SHALL）

#### Scenario: エラーなしの場合
- **WHEN** tmux capture-pane の出力にエラーパターンが含まれない
- **THEN** `check_error_output` は何も出力しない（SHALL）

### Requirement: テストスタブ state サブコマンド対応

`_stub_session_state` は `state` サブコマンドをサポートしなければならない（MUST）。`health-check.sh` L139 の `"$SESSION_STATE_CMD" state "$window"` 呼び出しに対応する。

#### Scenario: state サブコマンドで状態取得
- **WHEN** session-state.sh が `state <window>` で呼び出される
- **THEN** 設定された `window_state` 文字列を返さなければならない（SHALL）

#### Scenario: input_waiting 系テストの正常動作
- **WHEN** `_stub_session_state "input-waiting" N` でスタブが構成される
- **THEN** `state` サブコマンドは `input-waiting` を返し、`get` サブコマンドは JSON を返さなければならない（MUST）

## ADDED Requirements

### Requirement: health-report.sh レポート生成スクリプト

`health-report.sh` は検知パターンに基づく構造化 Markdown レポートをファイル出力しなければならない（MUST）。

#### Scenario: レポートファイル生成
- **WHEN** `--issue N --window NAME --pattern PATTERN --elapsed MINUTES --report-dir DIR` で実行される
- **THEN** `$DIR/issue-{N}-{YYYYMMDD-HHMMSS}.md` にレポートファイルを生成しなければならない（SHALL）

#### Scenario: レポート内容の構造
- **WHEN** レポートが生成される
- **THEN** 検知パターン、タイムスタンプ、tmux capture セクション、Issue Draft セクション（Title, 概要, 再現状況, 対応候補）を含まなければならない（MUST）

#### Scenario: Issue Draft のタイトル形式
- **WHEN** レポートの Issue Draft セクションが生成される
- **THEN** Title に `[autopilot]`、`Worker #N`、検知パターン名を含まなければならない（SHALL）

#### Scenario: ディレクトリ自動作成
- **WHEN** `--report-dir` のパスが存在しない
- **THEN** `mkdir -p` でディレクトリを自動作成しなければならない（MUST）

#### Scenario: gh issue create の禁止
- **WHEN** レポート生成が実行される
- **THEN** `gh issue create` や GitHub API 呼び出しを行ってはならない（MUST NOT）

#### Scenario: 必須引数の検証
- **WHEN** `--issue` または `--pattern` が未指定の場合
- **THEN** エラーメッセージを出力して異常終了しなければならない（SHALL）
