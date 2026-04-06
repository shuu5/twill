## Why

`autopilot-launch.md` の禁止事項セクションに `cld -p` / `cld --print` の使用禁止が記載されていないため、Pilot Claude が Worker 起動時に `-p` フラグを「プロンプト指定フラグ」と誤解し、Worker が非対話モード(print mode)で即終了するバグが 2026-03-30 に発生した。

## What Changes

- `commands/autopilot-launch.md` の禁止事項セクションに `cld -p` / `cld --print` 使用禁止ルールを追加
- Step 5 のコード例にコメントで `-p` フラグ禁止の注意書きを追加

## Capabilities

### New Capabilities

- なし

### Modified Capabilities

- Worker 起動コマンド構築の安全性向上: Pilot Claude が `-p` / `--print` フラグを使用するリスクを排除

## Impact

- 影響ファイル: `commands/autopilot-launch.md` のみ
- API 変更: なし
- 依存関係変更: なし
- リスク: 極めて低（ドキュメント追記のみ）
