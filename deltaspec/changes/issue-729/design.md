# Design: supervisor hook SESSION_ID path-traversal sanitization

## Goals

- supervisor hook 5 本（heartbeat, input-wait, input-clear, skill-step, session-end）で SESSION_ID をファイル名に埋め込む直前に allow-list サニタイズ（`[A-Za-z0-9_-]`）を適用し、path-traversal を根本防止する
- サニタイズで値が変化した場合は stderr に警告行を出力し、観測可能性を担保する（raw 値は出力しない）
- architecture spec（supervision.md）に SU-9 として明文化し、defense-in-depth の設計意図を記録する
- path-traversal テストケースおよび UUID 正常系テストを追加し、回帰防止を機械化する

## Non-Goals

- bare repo 構造ガード（別 Issue #728 の責務）
- `run_hook_with_autopilot()` 関数名乖離の修正（別 Issue #730）
- テスト副作用解消（別 Issue #731）
- Claude Code SDK 側の session_id 形式固定化（外部依存で制御不能）
- 他 hook スクリプト（`pre-bash-phase3-gate.sh` 等）の SESSION_ID 使用箇所（cksum 経由で数値化されるため path-traversal リスクなし）
- ADR 新規作成（既存 SU-* 表への追加のみで完結）
- stderr への raw SESSION_ID 値の出力（制御文字・過大サイズ注入リスクを避けるため明示的拒否）

## 変更点一覧

| ファイル | 変更内容 |
|----------|---------|
| `plugins/twl/scripts/hooks/supervisor-heartbeat.sh` | SESSION_ID 確定後・TMP_FILE 構築前にサニタイズブロック挿入 |
| `plugins/twl/scripts/hooks/supervisor-input-wait.sh` | SESSION_ID 確定後・TMP_FILE 構築前にサニタイズブロック挿入 |
| `plugins/twl/scripts/hooks/supervisor-input-clear.sh` | SESSION_ID 確定後・TARGET_FILE 構築前にサニタイズブロック挿入 |
| `plugins/twl/scripts/hooks/supervisor-skill-step.sh` | SESSION_ID 確定後・TMP_FILE 構築前にサニタイズブロック挿入 |
| `plugins/twl/scripts/hooks/supervisor-session-end.sh` | SESSION_ID 確定後・TMP_FILE 構築前にサニタイズブロック挿入 |
| `plugins/twl/architecture/domain/contexts/supervision.md` | SU-* 表末尾に SU-9 を新規追加 |
| `plugins/twl/tests/scenarios/supervisor-event-emission-hooks.test.sh` | `run_hook_capture_stderr()` helper 追加、path-traversal テスト・UUID 正常系テスト追加 |

## サニタイズブロック実装パターン

```bash
_SESSION_ID_RAW="$SESSION_ID"
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-')
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="$$"
fi
if [[ "$SESSION_ID" != "$_SESSION_ID_RAW" ]]; then
  printf '[supervisor-hook][warn] SESSION_ID sanitized (hook=%s pid=%s)\n' \
    "$(basename "$0")" "$$" >&2
fi
```

挿入位置は SESSION_ID フォールバック `fi` 行の直後、TMP_FILE/TARGET_FILE 構築の直前（input-clear は TMP_FILE を持たないため TARGET_FILE 直前のみ）。
