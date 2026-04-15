## Context

`autopilot-orchestrator.sh` の `inject_next_workflow()` (L882-991) は Worker session へ次の workflow を inject する責務を持つ。現在は以下の2つの問題がある:

1. `resolve_next_workflow` が non-terminal step で失敗するのは正常だが、WARNING レベルで出力されるため、異常との区別ができない
2. tmux capture-pane + regex による prompt 検出は Claude Code TUI の `❯` 表示と競合し、false positive/negative が発生する。また固定間隔リトライ（2秒×3回=6秒）はspecialist 並列実行中にタイムアウトする

前提: `session-state.sh` (#708 修正済み) が `input-waiting` を正確に返せることを前提とする。

## Goals / Non-Goals

**Goals:**
- `resolve_next_workflow` の exit=1 (non-terminal step) を TRACE に、予期せぬエラーを WARNING に分離する
- tmux capture-pane + regex の prompt 検出を `session-state.sh state` の `input-waiting` 検出に置換する
- prompt 検出リトライを exponential backoff (2s, 4s, 8s) に変更する
- trace ログに `RESOLVE_NOT_READY` / `RESOLVE_ERROR` / `INJECT_TIMEOUT` / `INJECT_SUCCESS` カテゴリを記録する

**Non-Goals:**
- issue-lifecycle-orchestrator.sh の inject 修正（#709）
- session-state.sh の false positive 修正（#708）
- 共通 inject lib の抽出（機構が根本的に異なるため見送り）

## Decisions

### 1. resolve ログ分離（L896-914）

`resolve_next_workflow` の失敗を2種類に分ける:

```bash
if [[ "$next_skill_exit" -ne 0 || -z "$next_skill" ]]; then
  # resolve_not_ready の判定: exit=1 かつ stderr に "not terminal" / "NOT_READY" が含まれる
  # それ以外の exit code やエラーは予期せぬエラー
  local _stderr_out
  _stderr_out=$(python3 -m twl.autopilot.resolve_next_workflow --issue "$issue" 2>&1 >/dev/null || true)
  if [[ "$next_skill_exit" -eq 1 ]]; then
    # NOT_READY: TRACE のみ（ポーリングサイクルで正常に発生する）
    echo "[${_trace_ts}] issue=${issue} category=RESOLVE_NOT_READY step=... result=skip" >> "$_trace_log" 2>/dev/null || true
  else
    # 予期せぬエラー: WARNING
    echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 予期せぬエラー — inject スキップ" >&2
    echo "[${_trace_ts}] issue=${issue} category=RESOLVE_ERROR exit=${next_skill_exit} result=skip" >> "$_trace_log" 2>/dev/null || true
  fi
```

`resolve_next_workflow` を2回呼ぶのは非効率なので、一度の呼び出しで stdout/stderr を分けて取得する。

**実装**: `$()` でstdout とexit codeを取得。exit=1 はNOT_READY（ポーリング正常）、exit≠0かつ≠1はERROR。

### 2. prompt 検出を session-state.sh に置換（L936-955）

tmux capture-pane + regex を削除し、SESSION_STATE_CMD で input-waiting を判定する:

```bash
local _state
_state=$(bash "$SESSION_STATE_CMD" state "$window_name" 2>/dev/null) || _state="unknown"
if [[ "$_state" != "input-waiting" ]]; then
  # backoff して再試行
fi
```

`SESSION_STATE_CMD` は既存の変数（autopilot-orchestrator.sh 冒頭付近で設定）を再利用する。

### 3. exponential backoff（L943-955）

固定 2秒×3回 を exponential backoff に変更:

```bash
for _i in 1 2 3; do
  _state=$(bash "$SESSION_STATE_CMD" state "$window_name" 2>/dev/null) || _state="unknown"
  if [[ "$_state" == "input-waiting" ]]; then
    prompt_found=1
    break
  fi
  sleep $(( 2 ** _i ))  # 2s, 4s, 8s
done
```

最大待機: 2+4+8=14秒。specialist 並列実行の processing 時間（~30秒）には不十分だが、backoff 自体は次のポーリングサイクル（POLL_INTERVAL）で再試行されるため問題ない。

### 4. trace ログカテゴリ追加

既存の trace ログに `category` フィールドを追加:
- `RESOLVE_NOT_READY`: exit=1 (non-terminal step, 正常)
- `RESOLVE_ERROR`: 予期せぬエラー
- `INJECT_TIMEOUT`: input-waiting が検出できなかった
- `INJECT_SUCCESS`: inject 成功

## Risks / Trade-offs

- **SESSION_STATE_CMD の可用性**: session-state.sh が存在しない環境ではフォールバックが必要。既存コードに SESSION_STATE_CMD チェックがあれば踏襲する
- **2回呼び出し問題**: resolve_next_workflow を stdout/stderr 分離のために2回呼ぶと副作用の可能性。実装では1回の呼び出しで stdout と exit code のみ取得し、exit=1/非1で分岐する（stderr は参照しない）
- **最大待機時間**: 2+4+8=14秒は long-running specialist には不十分。ただしポーリングサイクル（POLL_INTERVAL）での再試行で補完される
