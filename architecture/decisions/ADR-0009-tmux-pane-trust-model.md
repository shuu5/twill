# ADR-0009: tmux pane trust model と nudge inject 経路の脅威モデル

## ステータス

Accepted

## コンテキスト

`autopilot-orchestrator.sh` は `tmux send-keys` を介して Worker の Claude Code セッションにコマンドを inject する経路を 2 つ持つ:

1. **`inject_next_workflow`**: `python3 -m twl.autopilot.state resolve-next-workflow` から `current_step` 値を取得し、許可された次の workflow skill コマンドを inject する。
2. **`check_and_nudge`**: `tmux capture-pane` で Worker pane の出力テキストを取得し、`_nudge_command_for_pattern` でパターンマッチして nudge コマンドを決定し inject する。

`inject_next_workflow` は状態管理システム（`state JSON`）を信頼する入力源として使用するため、コマンドは機械的に決定される。一方 `check_and_nudge` は pane 出力テキスト（Worker の標準出力）を入力源とするため、より脆弱な信頼境界に置かれる。

## 決定

### 信頼する入力源 vs 信頼しない入力源

| 入力源 | 分類 | 理由 |
|--------|------|------|
| `.autopilot/issues/issue-N.json` の `current_step` フィールド | **信頼する** | `state write` は `--role pilot` / `--role worker` による書き込み制御下にある。直接 JSON 編集には OS レベルアクセスが必要 |
| `resolve-next-workflow` CLI 出力 | **信頼する** | `state JSON` を読み取るラッパーであり同等の保護下にある |
| `tmux capture-pane` pane 出力テキスト | **信頼しない** | Worker の Claude Code 標準出力であり、Worker が実行する MCP ツール・hook・外部コマンドの出力が混入する可能性がある。悪意ある MCP サーバーや hook が pane テキストを汚染できる |

### 脅威モデルの適用範囲

- **対象**: 同一ユーザー・同一 tmux セッション内のプロセス間信頼境界
- **対象外**: リモート攻撃者によるネットワーク経由のアクセス（tmux は local IPC であり、リモートアクセスは OS レベルの認証が必要）
- **想定される攻撃経路**:
  1. 悪意ある MCP サーバーが Worker の出力に `check_and_nudge` のパターン文字列を埋め込み、意図しないコマンドを inject させる
  2. Worker が実行する hook が pane テキストを汚染し `_nudge_command_for_pattern` に意図しない値を返させる

### 最終防衛線: `tmux send-keys` 直前の allow-list 検証

両経路ともに `tmux send-keys` を呼び出す直前で allow-list 検証を適用する:

```
正規表現: ^/twl:workflow-[a-z][a-z0-9-]*$
```

- `inject_next_workflow`: L832 でバリデーション済み（既存実装）
- `check_and_nudge`: Issue #496 で `tmux send-keys` 直前にバリデーションを追加（本 ADR の決定）

バリデーション失敗時は `tmux send-keys` を呼ばず WARNING ログと trace ログを出力してリターンする。

### `_nudge_command_for_pattern` の扱い

現時点では `_nudge_command_for_pattern` はハードコードされた `/twl:workflow-*` リテラル文字列のみを返す。しかし将来パターン追加時に `${issue}` 以外の変数（例: pane 出力から抽出した文字列）を埋め込んだ場合、allow-list なしでは injection 面が開く。

`check_and_nudge` と `_nudge_command_for_pattern` の呼び出し境界に allow-list を置くことで、内部実装の変更から防御を分離する。

## 結果

- `check_and_nudge` の `next_cmd` は `tmux send-keys` 直前で `^/twl:workflow-[a-z][a-z0-9-]*$` に一致しない場合は inject されない
- バリデーション失敗は `${AUTOPILOT_DIR}/trace/inject-YYYYMMDD.log` に記録される
- `inject_next_workflow` と `check_and_nudge` が対称な検証ロジックを持つようになり保守性が向上する

## 関連

- `plugins/twl/scripts/autopilot-orchestrator.sh`
  - `inject_next_workflow` L785（allow-list 実装済み, L832）
  - `check_and_nudge` L895（本 ADR で allow-list を追加）
  - `_nudge_command_for_pattern` L729（パターン定義）
- Issue #469 WARNING finding W3（phase-review）
- Issue #496（本 ADR を起票したセキュリティレビュー）
