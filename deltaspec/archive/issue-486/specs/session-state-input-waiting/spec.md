## MODIFIED Requirements

### Requirement: detect_state が tail-5 全体スキャンで input-waiting を判定する

`session-state.sh` の `detect_state()` は `PROMPT_PATTERN`（`❯[[:space:]]*$`）を `last_lines`（末尾5非空行）全体に適用しなければならない（SHALL）。末尾1行のみへの適用を廃止する。

#### Scenario: approval UI の選択肢行が tail-5 の中間にある場合
- **WHEN** capture-pane が `❯ 1. 承認して実行\n   Phase 1\n  2. キャンセル\nEnter to select · ↑/↓` を返す
- **THEN** `detect_state` が `input-waiting` を返す

#### Scenario: ❯ が最終行にある従来の input-waiting
- **WHEN** capture-pane の末尾行が `❯ ` で終わる
- **THEN** `detect_state` が `input-waiting` を返す（既存挙動を維持）

## ADDED Requirements

### Requirement: INPUT_WAITING_PATTERNS 配列による approval UI パターンのカバレッジ

`session-state.sh` は `INPUT_WAITING_PATTERNS` 配列を定義し、`last_lines` 全体に対してループでパターンを検索しなければならない（SHALL）。少なくとも以下のパターンを含む:
- `Enter to select`（Claude Code 選択 UI）
- `承認しますか`（日本語 AskUserQuestion）
- `Do you want to`（英語 AskUserQuestion）
- `[y/N]`（y/N プロンプト）

#### Scenario: Claude Code 選択 UI を input-waiting と判定する
- **WHEN** capture-pane に `Enter to select · ↑/↓ to navigate · Esc to cancel` が含まれる
- **THEN** `detect_state` が `input-waiting` を返す

#### Scenario: 日本語 AskUserQuestion を input-waiting と判定する
- **WHEN** capture-pane に `承認しますか？` が含まれる
- **THEN** `detect_state` が `input-waiting` を返す

#### Scenario: 英語 y/N プロンプトを input-waiting と判定する
- **WHEN** capture-pane に `[y/N]` が含まれる
- **THEN** `detect_state` が `input-waiting` を返す

### Requirement: session-state.sh の bats テストが approval UI パターンを検証する

`plugins/session/tests/` 配下に bats テストを追加し、`detect_state()` が approval UI パターン 3 種以上を `input-waiting` と返すことを検証しなければならない（MUST）。tmux 依存なしで実行可能なモックアプローチを採用する。

#### Scenario: bats テストが approval UI 3 種をカバーする
- **WHEN** `session-state.sh detect_state` テストが実行される
- **THEN** `Enter to select` / 日本語承認 / `[y/N]` の 3 パターン以上が `input-waiting` として検証される

#### Scenario: processing UI が input-waiting と誤判定されない
- **WHEN** capture-pane に `Thinking...` や `Working...` のみが表示されている
- **THEN** `detect_state` が `processing` を返す
