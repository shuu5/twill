## Context

`autopilot-orchestrator.sh` には 2 つの tmux inject 経路がある。

1. **`inject_next_workflow`** (L785): `current_step` terminal 値ベース。L822-836 で allow-list `^/twl:workflow-[a-z][a-z0-9-]*$` を適用済み。
2. **`check_and_nudge`** (L895): pane 出力テキストパターンベース。`_nudge_command_for_pattern` の返り値を L922 で検証なしに `tmux send-keys` に直接渡す。

現時点では `_nudge_command_for_pattern` がハードコードされた `/twl:workflow-*` リテラルしか返さないため実害はない。しかし将来のパターン追加時に `${issue}` 以外の変数を埋め込んだ場合、injection 面が開く。また tmux pane 出力は同一セッション内の別プロセスが操作可能であり、Worker の Claude Code 出力を汚染することで `_nudge_command_for_pattern` に意図しない文字列を返させる経路が存在する。

## Goals / Non-Goals

**Goals:**
- `check_and_nudge` の `next_cmd` を `tmux send-keys` に渡す直前に allow-list バリデーションを適用する
- バリデーション失敗時に WARNING ログと trace ログを出力し nudge をスキップする
- `inject_next_workflow` と `check_and_nudge` の検証ロジックを対称にする
- shunit2 テストで既存 7 パターンの通過と不正パターンのブロックを確認する
- ADR で tmux pane trust model を明文化する

**Non-Goals:**
- `_nudge_command_for_pattern` の内部ロジック変更
- `inject_next_workflow` の変更
- tmux 外部からのアクセス制御（OS レベルのセキュリティは対象外）
- Worker 出力の汚染防止そのもの（最終防衛線は inject 直前の検証）

## Decisions

### 1. バリデーション正規表現

`inject_next_workflow` L832 と同じ正規表現を使用:
```bash
^/twl:workflow-[a-z][a-z0-9-]*$
```
空文字列（`""`）は `_nudge_command_for_pattern` が「無操作」を表すため check_and_nudge 内で `[[ -n "$next_cmd" ]]` によって既に弾かれる。バリデーションは非空かつ不一致の場合に WARNING を出す。

### 2. 配置箇所

`check_and_nudge` L920-922 の `tmux send-keys` 呼び出し直前に挿入する。具体的には:
```bash
if next_cmd="$(_nudge_command_for_pattern "$pane_output" "$issue" "$entry")" && [[ -n "$next_cmd" ]]; then
  # ← ここにバリデーションを追加
  if [[ ! "$next_cmd" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
    echo "[orchestrator] Issue #${issue}: WARNING: check_and_nudge — 不正な next_cmd '${next_cmd:0:200}' — nudge スキップ" >&2
    # trace ログ出力
    return 0
  fi
  echo "[orchestrator] Issue #${issue}: chain 遷移停止検知 — nudge 送信 ..." >&2
  tmux send-keys -t "$window_name" "$next_cmd" Enter 2>/dev/null || true
```

### 3. trace ログ

`inject_next_workflow` の trace ログと同形式でファイルに記録する。変数 `_trace_log` は `inject_next_workflow` のスコープで定義されているため `check_and_nudge` 内では独立して trace ログパスを解決するか、共通ヘルパーに切り出す。
簡易実装として `check_and_nudge` 内で trace ログパスを直接組み立てる（`inject_next_workflow` と同じパス命名規則）。

### 4. ADR

`architecture/adr/` ディレクトリに新規 ADR を作成。番号は既存の最大番号 + 1 を使用。

## Risks / Trade-offs

- **正規表現の共通化**: `inject_next_workflow` と `check_and_nudge` でコピーになるが、現時点では単純化のためコピーを選択。共通関数化はスコープ外
- **trace ログパスの重複**: `check_and_nudge` 内で `_trace_log` を再定義すると保守性が下がる。将来は共通関数化が望ましい
- **shunit2 テスト**: `_nudge_command_for_pattern` の出力がハードコード文字列のため、allow-list は全て通過する。「不正パターンのブロック」テストは `check_and_nudge` のモックテストとして実装する
