## ADDED Requirements

### Requirement: Bash エラー自動記録

PostToolUse hook により、Bash tool の exit_code != 0 を `.self-improve/errors.jsonl` に JSONL 形式で自動記録しなければならない（SHALL）。

記録フォーマット:
```json
{"timestamp": "ISO8601", "command": "先頭200文字", "exit_code": N, "stderr_snippet": "先頭500文字", "cwd": "/path/to/dir"}
```

hook はサイレント・ノンブロッキングで実行し、記録の成功・失敗にかかわらず exit 0 を返さなければならない（MUST）。

#### Scenario: 正常なエラー記録
- **WHEN** Bash tool が exit_code 1 で終了する
- **THEN** `.self-improve/errors.jsonl` に timestamp, command, exit_code, stderr_snippet, cwd を含む JSON 行が追記される

#### Scenario: 成功時は記録しない
- **WHEN** Bash tool が exit_code 0 で終了する
- **THEN** `.self-improve/errors.jsonl` には何も追記されない

#### Scenario: command の切り詰め
- **WHEN** 実行されたコマンドが 200 文字を超える
- **THEN** command フィールドは先頭 200 文字に切り詰められる

#### Scenario: stderr_snippet の切り詰め
- **WHEN** stderr 出力が 500 文字を超える
- **THEN** stderr_snippet フィールドは先頭 500 文字に切り詰められる

#### Scenario: 環境変数が利用不可の場合のフォールバック
- **WHEN** PostToolUse 環境変数（TOOL_INPUT, TOOL_OUTPUT）が空または未設定である
- **THEN** command は空文字列、stderr_snippet は空文字列としてフォールバック記録される

## MODIFIED Requirements

### Requirement: .self-improve ディレクトリの自動作成

hook は `.self-improve/` ディレクトリが存在しない場合、自動的に作成しなければならない（MUST）。

#### Scenario: 初回記録時のディレクトリ作成
- **WHEN** `.self-improve/` ディレクトリが存在せず、Bash エラーが発生する
- **THEN** `.self-improve/` ディレクトリが作成され、errors.jsonl に記録が書き込まれる
