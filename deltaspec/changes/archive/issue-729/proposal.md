## Why

supervisor hook 5 本（heartbeat, input-wait, input-clear, skill-step, session-end）が `SESSION_ID` をファイル名に直接埋め込む際にサニタイズを行っておらず、path-traversal 攻撃が可能な状態にある。悪意ある SESSION_ID（例: `../../etc/passwd`）が注入された場合、hook スクリプトが任意パスにファイルを書き込む可能性がある。

## What Changes

- supervisor hook 5 本すべてで SESSION_ID フォールバック直後・TMP_FILE/TARGET_FILE 構築前に allow-list サニタイズブロック（`[A-Za-z0-9_-]`）を挿入する
- サニタイズで値が変化した場合は stderr に警告行を出力し、raw SESSION_ID 値は出力しない
- `plugins/twl/architecture/domain/contexts/supervision.md` の SU-* 表末尾に SU-9（SESSION_ID sanitization）を新規追加する
- `supervisor-event-emission-hooks.test.sh` に path-traversal テストケースおよび UUID 正常系テストを追加する

## Capabilities

### New Capabilities

- supervisor hook が path-traversal 攻撃を防御する
- サニタイズ警告を stderr に出力することで異常な SESSION_ID の検出が可能になる
- SU-9 として architecture spec に明文化することで defense-in-depth の設計意図が記録される

### Modified Capabilities

- supervisor hook の SESSION_ID 処理: 未サニタイズ → allow-list `[A-Za-z0-9_-]` サニタイズ適用
- 全 5 hook（heartbeat, input-wait, input-clear, skill-step, session-end）に同一サニタイズパターンを適用

## Impact

**変更ファイル:**
- `plugins/twl/scripts/hooks/supervisor-heartbeat.sh`
- `plugins/twl/scripts/hooks/supervisor-input-wait.sh`
- `plugins/twl/scripts/hooks/supervisor-input-clear.sh`
- `plugins/twl/scripts/hooks/supervisor-skill-step.sh`
- `plugins/twl/scripts/hooks/supervisor-session-end.sh`
- `plugins/twl/architecture/domain/contexts/supervision.md`
- `plugins/twl/tests/scenarios/supervisor-event-emission-hooks.test.sh`

**依存関係:**
- サニタイズブロックは SESSION_ID フォールバック `fi` 行の直後、ファイルパス構築の直前に挿入する制約あり
- input-clear は TMP_FILE を持たないため TARGET_FILE 直前のみに挿入
