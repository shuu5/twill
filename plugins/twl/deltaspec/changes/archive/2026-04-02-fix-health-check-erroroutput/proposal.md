## Why

PR #94（#79）の merge-gate で code-reviewer が CRITICAL 3件を検出。health-check.sh の多行エラー出力パース破壊、テストスタブの `state` サブコマンド未実装、health-report.sh 未存在によりテストが偽陽性または実行不能になっている。

## What Changes

- `scripts/health-check.sh`: `check_error_output` の多行出力を1行に正規化（改行→セミコロン変換）
- `tests/bats/scripts/health-check.bats`: `_stub_session_state` に `state` サブコマンドを追加
- `scripts/health-report.sh`: 新規作成（health-check.sh から検出されたパターンに対するレポート生成）
- `tests/bats/scripts/health-report.bats`: 既存テストが新スクリプトで実行可能になるよう整合

## Capabilities

### New Capabilities

- `health-report.sh`: 検知パターン・Issue番号・tmux capture を引数で受け取り、構造化レポート（Markdown）をファイル出力するスクリプト

### Modified Capabilities

- `health-check.sh` の `check_error_output`: 多行エラーを1行に正規化し、結果集約ループでのパース破壊を防止
- `health-check.bats` の `_stub_session_state`: `state` サブコマンドに対応し、input_waiting 系テスト7件が正しく検知ロジックを通過

## Impact

- **scripts/health-check.sh**: L129 の出力形式変更（多行→1行）。結果集約ループ（L175）のパース動作に影響
- **tests/bats/scripts/health-check.bats**: スタブ関数の拡張。既存テストの動作変更なし
- **scripts/health-report.sh**: 新規ファイル追加。autopilot-phase-execute から呼び出される想定
- **tests/bats/scripts/health-report.bats**: 既存テストファイル。呼び出し先が存在するようになる
