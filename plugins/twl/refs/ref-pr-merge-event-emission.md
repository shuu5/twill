# ref-pr-merge-event-emission — WAVE-PR-MERGED イベント発火の技術メモ

Issue #1428 実装メモ。Layer 1 post-merge event emitter の設計判断と運用上の注意を記載する。

## 概要

`chain-runner.sh::step_auto_merge` が auto-merge 成功直後に
`emit-wave-pr-merged-event.sh` を呼び出し、以下の 2 つを実行する:

1. `.supervisor/events/wave-{N}-pr-merged-{issue}.json` への event ファイル atomic write
2. `twl_notify_supervisor_handler` による mailbox push（`supervisor` 宛て）

## mailbox push 失敗時のフォールバック

`twl_notify_supervisor_handler` の呼び出しが失敗した場合（import エラー、mailbox write エラー等）:

- **WARN ログ** を stderr に出力するのみで exit 0 を返す（best-effort）
- **events/ ファイルは既に atomic write 完了**しているため SSoT として残る
- Layer 2 watchdog（S3 = 別 Issue）が `inotify` または polling で events/ を監視し、
  mailbox push を補完できる設計とする

**結論**: events/ ファイルが primary SSoT であり、mailbox push は delivery 最適化（low-latency）に過ぎない。
watchdog は専用 glob パターン `wave-*-pr-merged-*.json` で拾う。

## wave 番号取得とフォールバック

- `.supervisor/wave-queue.json` の `current_wave` フィールドを参照する
- ファイル不在 / フィールド不在 / 非整数値の場合: `wave=-1` で続行
- `wave=-1` の event JSON には `"warning"` フィールドを追加し、
  watchdog が異常状態であることを把握できるようにする

## event ファイル命名規則

`wave-{N}-pr-merged-{issue}.json`（例: `wave-3-pr-merged-1428.json`）

既存の `{EVENT_NAME}-{window}-{timestamp}.json` 規則と異なるが**意図的**:
- wave progress event は issue/wave 番号で一意に識別できるためタイムスタンプ不要
- watchdog が専用 glob で識別しやすくするため小文字 + 固定フォーマット

## atomic write の実装

```bash
TMPFILE="$(mktemp "${EVENTS_DIR}/.wave-pr-merged-${ISSUE_NUM}.XXXXXX.tmp")"
echo "$PAYLOAD_JSON" > "$TMPFILE" && mv "$TMPFILE" "$EVENT_FILE"
```

`mv` は同一ファイルシステム上で POSIX atomic であり、
watchdog が部分書き込みを読む可能性を排除する。

## 実装ファイル

- `plugins/twl/scripts/emit-wave-pr-merged-event.sh` — event 生成 + notify (新規)
- `plugins/twl/scripts/chain-runner.sh` — `step_auto_merge` に hook 追加 (#1428)
