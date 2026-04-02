## Why

Pilot (Opus) の context が orchestrator.sh のポーリングログで汚染されている。orchestrator は60分以上動作する間、大量の進捗ログを stdout に出力し、それが Bash tool output として Pilot の context window に蓄積される。また、postprocess のトークン消費量が可視化されていないため、異常な長時間処理を検出できない。

## What Changes

- `autopilot-orchestrator.sh` の全 `echo "[orchestrator]..."` 行に `>&2` を追加し、stdout を JSON レポートのみに限定
- `autopilot-orchestrator.sh` の Phase 実行開始時に `mkdir -p "$AUTOPILOT_DIR/logs"` を追加
- `co-autopilot/SKILL.md` の orchestrator 呼び出しを `REPORT=$(bash ... 2>"$AUTOPILOT_DIR/logs/phase-${P}.log")` 形式に変更
- `autopilot-phase-postprocess.md` に開始・終了タイムスタンプ記録と session.json への `token_estimate` 書き込みを追加

## Capabilities

### New Capabilities

- **ログファイル保存**: orchestrator の進捗ログが `$AUTOPILOT_DIR/logs/phase-N.log` に保存され、事後デバッグに利用可能
- **Token Estimate 記録**: postprocess 完了時に session.json の retrospective エントリに `token_estimate`（経過時間ベース推定）が記録される

### Modified Capabilities

- **Pilot context の純化**: Pilot が受け取る Bash tool output は orchestrator の JSON レポートのみになり、進捗ログが排除される
- **orchestrator stdout の限定**: `generate_phase_report` の JSON 出力のみが stdout に流れる

## Impact

- `scripts/autopilot-orchestrator.sh`: echo 行への `>&2` 追加（機械的変更）
- `skills/co-autopilot/SKILL.md`: orchestrator 呼び出しのリダイレクト変更
- `commands/autopilot-phase-postprocess.md`: タイムスタンプと token_estimate ロジック追加
- `.autopilot/logs/` ディレクトリが runtime に自動作成（git 管理外）
