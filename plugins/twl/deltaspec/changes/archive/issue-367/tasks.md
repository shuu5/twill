## 1. externalize-state コマンド作成

- [ ] 1.1 `plugins/twl/commands/externalize-state.md` を新規作成する
- [ ] 1.2 `--trigger` 引数（`auto_precompact` / `manual` / `wave_complete`）のハンドリングを実装する
- [ ] 1.3 `refs/externalization-schema.md` を参照し、書き出しファイルのフロントマター・本文を生成する
- [ ] 1.4 `trigger=wave_complete` の場合に `.autopilot/session.json` から `current_wave` を読み出して `wave-{N}-summary.md` に書き出す
- [ ] 1.5 その他のトリガーでは `.autopilot/working-memory.md` に書き出す

## 2. ExternalizationRecord 追記

- [ ] 2.1 実行後に `.autopilot/session.json` の `externalization_log` 配列に `externalized_at`・`trigger`・`output_path` を追記する

## 3. deps.yaml 登録

- [ ] 3.1 `plugins/twl/deps.yaml` に `externalize-state` エントリ（type: atomic, effort: low）を追加する
- [ ] 3.2 `su-compact` の `calls` に `externalize-state` を追加する
- [ ] 3.3 `twl check` でエラーなし確認する
- [ ] 3.4 `twl update-readme` を実行する
