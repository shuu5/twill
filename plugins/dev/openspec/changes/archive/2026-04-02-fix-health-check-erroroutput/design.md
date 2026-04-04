## Context

health-check.sh は autopilot の各 worker ウィンドウを監視し、chain_stall / error_output / input_waiting の3パターンを検知する。検知結果は `pattern:detail` 形式で stdout に出力され、結果集約ループ（L175）で `IFS= read -r line` により1行ずつ読み取られる。

現状3つの問題がある:
1. `check_error_output` が `head -5` で複数行を出力 → 2行目以降が `pattern:detail` 形式を崩す
2. テストスタブ `_stub_session_state` に `state` サブコマンドがない → `*) exit 1` に落ちる
3. `health-report.bats` が `scripts/health-report.sh` を呼び出すが、このファイルが存在しない

## Goals / Non-Goals

**Goals:**

- 多行エラー出力を1行に正規化して結果集約ループのパースを保護する
- テストスタブに `state` サブコマンドを追加して input_waiting 系テスト7件を修正する
- `health-report.sh` を新規作成して既存17テストを実行可能にする
- `loom check` PASS を維持する

**Non-Goals:**

- health-check.sh のアーキテクチャ変更（検知パターンの追加・削除）
- autopilot-phase-execute 側の呼び出しロジック変更
- health-report の出力フォーマット仕様の再設計

## Decisions

### D1: 多行→1行の正規化方法

`echo "$error_lines" | head -5 | tr '\n' '; ' | sed 's/; $//'` でセミコロン区切りに変換。
- 理由: パイプラインに tr を追加するだけで最小変更。パース側の変更不要
- 代替案: 配列に格納して各行個別出力 → 結果集約ループの変更が必要で影響範囲が大きい

### D2: health-report.sh のインターフェース

既存テスト（health-report.bats）が定義するインターフェースに合わせる:
- `--issue N --window NAME --pattern PATTERN --elapsed MINUTES --report-dir DIR`
- 出力: `$report-dir/issue-{N}-{YYYYMMDD-HHMMSS}.md`
- テストが仕様 → テストを変更せずスクリプトを実装する

### D3: state サブコマンドのスタブ実装

`_stub_session_state` に `state)` case を追加。引数 `$window_state` を返す。
- `get` サブコマンドの既存動作には `input-waiting` が入ることを想定し、`state` では状態文字列のみ返す

## Risks / Trade-offs

- **セミコロン区切り**: エラーメッセージ自体にセミコロンが含まれる場合、表示上の区切りが曖昧になる。ただし `error_output` パターンの detail は人間向け表示であり、機械パースには使用されないため許容可能
- **health-report.sh 新規作成**: テストが仕様を定義しているが、テスト自体に不備がある可能性がある。既存テストの assert を信頼して実装する
