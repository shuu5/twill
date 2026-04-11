## Why

`su-observer` が supervise モード中に Monitor tool（Pilot tail streaming）のみを使用し、Worker window の状態と state file の stagnate を監視していなかったため、Wave 5 で Worker stall が 90 分間検知できなかった。監視チャンネルの使い分けと state stagnate 検知ロジックが未定義であることが根本原因。

## What Changes

- `plugins/twl/skills/su-observer/SKILL.md` — Step 1 に監視チャンネルマトリクスと state stagnate 検知手順を追加
- `plugins/twl/commands/observe-once.md` — state file mtime チェックと Worker window 集約 capture を追加
- `plugins/twl/refs/intervention-catalog.md` — Layer 0 Auto「Worker idle 検知パターン」（pattern-7）を追加
- `tests/scenarios/` — cld-observe-loop 連携の dry-run テストシナリオを追加

## Capabilities

### New Capabilities

- **監視チャンネルマトリクス**: su-observer SKILL.md に Monitor(Pilot) / cld-observe-loop(Workers) / state mtime / session-comm capture / gh pr list の5チャンネルを明示し、supervise 1 iteration での並行実行手順を定義する
- **state stagnate 検知**: observe-once が `.autopilot/issues/issue-*.json` の `updated_at` を読み、`AUTOPILOT_STAGNATE_SEC`（デフォルト 600s）以上経過していれば WARN を出力する
- **Worker idle 介入パターン（pattern-7）**: intervention-catalog に「state stagnate AND worker pane に `>>> 実装完了:` を含む」場合の Layer 0 Auto 介入手順を追加

### Modified Capabilities

- **observe-once**: 単一 window capture に加え、Worker window 群（glob pattern `ap-*`）の集約 capture と state mtime チェックを実行するモードを追加
- **su-observer supervise ループ**: 1 iteration で Pilot Monitor streaming + cld-observe-loop による Worker polling + state stagnate check を並行実行するよう Step 1 を拡張

## Impact

- `plugins/twl/skills/su-observer/SKILL.md` — Step 1 監視チャンネルマトリクス追加（+20-30 行）
- `plugins/twl/commands/observe-once.md` — state mtime チェックロジック追加（+15 行）
- `plugins/twl/refs/intervention-catalog.md` — pattern-7 追加（+20 行）
- `tests/scenarios/` — 新規テストシナリオ 1 ファイル追加
- `AUTOPILOT_STAGNATE_SEC` 環境変数: #469/#472 と共通値を参照（未定義時デフォルト 600）
