## Context

`session-state.sh` の `detect_state()` は tmux pane の最終行テキストを解析し、Claude Code の状態（`input-waiting` / `processing` / `idle`）を判定する。現行 L158-166 のフォールバックロジックは `"bypass permissions"` と `"esc to interrupt"` を OR 条件で束ねており、後者（LLM 実行中に status bar へ表示される）でも `input-waiting` に分類してしまう。processing indicator の否定チェック（Thinking/Working 等）は ephemeral な TUI 要素であり、tmux capture-pane のタイミング依存で信頼性が低い。

## Goals / Non-Goals

**Goals:**
- `"esc to interrupt"` 単独表示 → `processing` を返すよう修正
- `"bypass permissions"` 単独表示 → `input-waiting` を返す（現行動作維持）
- `"bypass permissions"` + `"esc to interrupt"` 同時表示 → `input-waiting` を返す（bypass 優先）
- processing indicator 否定チェック（L162）を削除し、判定ロジックを単純化
- 既存テスト 12 件 PASS + 新規テスト 4 件追加で計 16 件 PASS

**Non-Goals:**
- `session-comm.sh`, `cld-spawn`, `cld-observe` 等の変更
- `detect_state()` のアーキテクチャ全体の再設計
- 他の状態判定パターン（`idle`, `error` 等）の変更

## Decisions

**分岐順序**:
1. `"bypass permissions"` を先にチェック → `input-waiting`（権限プロンプトは常に優先）
2. `"esc to interrupt"` をその後にチェック → `processing`

この順序により、両方表示時は `"bypass permissions"` チェックが先にヒットし、`input-waiting` が返る。OR 条件より明示的で意図が明確。

**処理 indicator 否定チェック削除**:
`"esc to interrupt"` 自体が最も信頼性の高い processing indicator であるため、`Thinking`/`Working` 等の否定チェックは不要。ephemeral な要素への依存を排除する。

**変更箇所の最小化**:
L158-166 の 9 行を 8 行に置換。インターフェース（返り値の文字列セット）は変更なし。

## Risks / Trade-offs

- **リスク**: `"bypass permissions"` + `"esc to interrupt"` が同時に表示されるエッジケースは稀だが、意図的に bypass 優先とした。Claude Code が権限プロンプト表示中に status bar の `"esc to interrupt"` が残留するケースを想定。
- **トレードオフ**: processing indicator 否定チェックを削除することで、将来新しい indicator が追加された場合の考慮が不要になる（シンプル化）。
