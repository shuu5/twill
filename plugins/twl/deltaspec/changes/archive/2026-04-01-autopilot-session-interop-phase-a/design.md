## Context

autopilot の Worker 監視は crash-detect.sh（tmux list-panes）+ autopilot-poll（sleep 10 ループ）の 2 層構成。ubuntu-note-system に Session Interop 基盤（session-state.sh）が構築済みであり、5 状態検出（idle/input-waiting/processing/error/exited）と wait サブコマンドが利用可能。

session-state.sh のインターフェース:
- `session-state.sh state <window>` → 状態文字列を stdout に出力
- `session-state.sh wait <window> <state> [--timeout N]` → 指定状態到達まで sleep 1 ループ（デフォルト 30 秒タイムアウト）
- 5 状態: idle / input-waiting / processing / error / exited

外部依存: `~/ubuntu-note-system/scripts/session-state.sh`（本リポジトリ外）

## Goals / Non-Goals

**Goals:**

- crash-detect.sh を session-state.sh の 5 状態検出に置換し、exited/error を区別可能にする
- session-state.sh 非存在時に既存の tmux list-panes ベース検知にフォールバック
- autopilot-poll.md で session-state.sh wait の活用を記述
- 既存テスト 8 件を新インターフェースに更新

**Non-Goals:**

- /observe ベースの proactive monitoring（#79 スコープ）
- session-comm.sh の inject 機能活用（#79 スコープ）
- session-state.sh wait の sleep 間隔変更（upstream 側の変更）
- autopilot-poll の全面的なアーキテクチャ変更（本 Phase はインターフェース置換のみ）

## Decisions

### D1: フォールバック戦略 — session-state.sh 非存在時は既存ロジック維持

crash-detect.sh 冒頭で `SESSION_STATE_CMD` を解決。存在すれば session-state.sh、不在なら `USE_SESSION_STATE=false` で従来の tmux list-panes パスにフォールバック。

```bash
SESSION_STATE_CMD="${SESSION_STATE_CMD:-$HOME/ubuntu-note-system/scripts/session-state.sh}"
if [[ -x "$SESSION_STATE_CMD" ]]; then
  USE_SESSION_STATE=true
else
  USE_SESSION_STATE=false
fi
```

**理由**: session-state.sh は外部リポジトリ依存であり、全環境での存在を保証できない。

### D2: 状態マッピング — session-state.sh の 5 状態を autopilot アクションに変換

| session-state.sh 状態 | autopilot での扱い | exit code |
|---|---|---|
| processing | Worker 稼働中 → 正常 | 0 |
| idle | Worker 待機中 → 正常（プロンプト不在時） | 0 |
| input-waiting | Worker 入力待ち → 正常 | 0 |
| error | Worker エラー状態 → crash 扱い | 2 |
| exited | Worker 終了 → crash 扱い | 2 |

**理由**: error と exited は Worker が自律的に回復できない状態。autopilot の crash リカバリフローに乗せる。

### D3: autopilot-poll での wait 活用 — タイムアウト付き wait ループ

autopilot-poll の single/phase ポーリングで、session-state.sh 存在時は `wait` サブコマンドを利用。ただし wait のデフォルト timeout=30 秒を超えたら state を直接チェックするループに戻る形式とする。

```
while not resolved:
  session-state.sh wait <window> exited --timeout 10
  state = session-state.sh state <window>
  # state に基づき判定
```

**理由**: wait は単一状態しか待てないが、autopilot は exited/error/input-waiting 複数状態を監視する必要がある。短い timeout で wait → state チェックのサイクルを回す。

### D4: failure メッセージに状態情報を含める

crash 検知時の failure JSON に `detected_state` フィールドを追加し、exited と error を区別可能にする。

```json
{
  "message": "Worker error detected via session-state: error",
  "step": "current_step",
  "timestamp": "...",
  "detected_state": "error"
}
```

## Risks / Trade-offs

- **session-state.sh の状態検出精度**: capture-pane ベースのパターンマッチのため、Claude Code UI 変更時に誤検知の可能性。ただしフォールバックがあるため致命的ではない
- **sleep 1 ループの CPU 負荷**: session-state.sh wait は sleep 1 間隔。現行の sleep 10 より頻度が上がるが、tmux コマンドは軽量なため実用上問題なし
- **外部依存の結合度**: session-state.sh のインターフェース変更時にbreak する可能性。`SESSION_STATE_CMD` 環境変数でパスを上書き可能にして緩和
