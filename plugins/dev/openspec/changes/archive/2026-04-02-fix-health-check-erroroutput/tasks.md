## 1. 多行エラー出力パース修正

- [x] 1.1 `scripts/health-check.sh` L129: `echo "$error_lines" | head -5` の出力を `tr '\n' '; ' | sed 's/; $//'` で1行に正規化

## 2. テストスタブ state サブコマンド追加

- [x] 2.1 `tests/bats/scripts/health-check.bats` の `_stub_session_state` に `state)` case を追加（`echo "$window_state"` を返す）
- [x] 2.2 `_stub_session_state` の `get)` case で input-waiting 用 JSON を返すよう修正（`{"since": <epoch>}` 形式）

## 3. health-report.sh 新規作成

- [x] 3.1 `scripts/health-report.sh` を新規作成: 引数パース（--issue, --window, --pattern, --elapsed, --report-dir）
- [x] 3.2 レポートファイル出力: `issue-{N}-{YYYYMMDD-HHMMSS}.md` 形式、構造化 Markdown（パターン、タイムスタンプ、tmux capture、Issue Draft）
- [x] 3.3 ディレクトリ自動作成（mkdir -p）、必須引数検証、gh 呼び出し禁止

## 4. テスト実行・検証

- [x] 4.1 `bats tests/bats/scripts/health-check.bats` 全テスト PASS 確認（49/49）
- [x] 4.2 `bats tests/bats/scripts/health-report.bats` 全19テスト PASS 確認
- [x] 4.3 `loom check` PASS 確認（OK: 148, Missing: 0）
