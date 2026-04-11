## 1. autopilot-orchestrator.sh: nohup 実行モード + trace ログ

- [x] 1.1 `plugins/twl/scripts/autopilot-orchestrator.sh`: `.autopilot/trace/` ディレクトリ作成処理を追加（`mkdir -p "${AUTOPILOT_DIR}/trace"`）
- [x] 1.2 `inject_next_workflow()` に trace ログ記録処理を追加（成功/失敗/理由を `.autopilot/trace/inject-{YYYYMMDD}.log` に追記）
- [x] 1.3 tmux send-keys のエラーを trace ログにリダイレクト（`/dev/null` への silent discard を排除）
- [x] 1.4 orchestrator の PID と起動時刻を trace ログに記録する処理を追加

## 2. co-autopilot SKILL.md: chain bypass 禁止ルール追加

- [x] 2.1 `plugins/twl/skills/co-autopilot/SKILL.md` の Step 4 orchestrator 起動コードを nohup/disown パターンに変更
- [x] 2.2 PHASE_COMPLETE 検知ロジック（`tail -f` + grep）を Step 4 に追加
- [x] 2.3 「chain 停止時の復旧手順」セクションを追加（orchestrator 再起動 or 手動 `/twl:workflow-<name>` inject）
- [x] 2.4 「禁止事項（MUST NOT）」セクションに chain bypass 禁止を追加（不変条件 M 参照）

## 3. autopilot.md: 不変条件 M 追加

- [x] 3.1 `plugins/twl/architecture/domain/contexts/autopilot.md` の不変条件テーブルに不変条件 M を追加
- [x] 3.2 不変条件数を「12件」→「13件」に更新
