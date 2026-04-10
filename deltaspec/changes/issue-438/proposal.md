## Why

autopilot-orchestrator の polling loop が Pilot の Bash context 内で実行されるため、timeout/cancel で停止し `inject_next_workflow()` が呼ばれない。結果として setup → test-ready → pr-verify の chain 遷移が全て停止し、specialist review を含む pr-verify chain がスキップされる。Wave 18-25 で 28 PRs が specialist review なしでマージされた。

## What Changes

- `plugins/twl/scripts/autopilot-orchestrator.sh`
  - Pilot Bash context 外で持続する実行モードを追加（nohup/disown による独立プロセス化）
  - `inject_next_workflow()` の実行結果（成功/失敗/理由）を `.autopilot/trace/` に記録し、silent fail を排除
- `plugins/twl/skills/co-autopilot/SKILL.md`
  - chain bypass 禁止（Worker chain 停止時は orchestrator 再起動 or 手動 re-inject のみ）を明記
  - chain 停止時の正規復旧手順を追加
- `plugins/twl/architecture/domain/contexts/autopilot.md`
  - 不変条件 M「chain 遷移は orchestrator inject または手動 skill inject のみ。Pilot の直接 nudge による chain bypass は禁止」を追加

## Capabilities

### New Capabilities

- orchestrator が Pilot の Bash timeout/cancel に影響されず持続する（nohup 実行モード）
- `inject_next_workflow()` の実行ログが `.autopilot/trace/` に書き込まれ、デバッグ可能になる
- 不変条件 M により chain bypass パターンがルールレベルで禁止される

### Modified Capabilities

- orchestrator 起動: Pilot は Bash 直接実行ではなく nohup/disown 経由で起動する
- co-autopilot SKILL.md: chain 停止時の手順が「orchestrator 再起動 or 手動 re-inject」に限定され、直接 nudge が禁止される

## Impact

- `plugins/twl/scripts/autopilot-orchestrator.sh`（実行モード変更、ログ追加）
- `plugins/twl/skills/co-autopilot/SKILL.md`（chain bypass 禁止ルール追加）
- `plugins/twl/architecture/domain/contexts/autopilot.md`（不変条件 M 追加）
