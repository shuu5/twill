## 1. allow-list 検証追加

- [ ] 1.1 `check_and_nudge` (L920-922 付近) に allow-list バリデーションを挿入: `next_cmd` が `^/twl:workflow-[a-z][a-z0-9-]*$` に一致しない場合は WARNING ログを出力して `return 0`
- [ ] 1.2 バリデーション失敗時の trace ログ出力を追加（`inject_next_workflow` と同形式のファイルに記録）

## 2. ADR 作成

- [ ] 2.1 `architecture/decisions/ADR-0009-tmux-pane-trust-model.md` を新規作成（信頼境界、信頼する入力源 vs 信頼しない入力源、最終防衛線の明文化）

## 3. shunit2 テスト追加

- [ ] 3.1 `test-fixtures/` 配下に shunit2 テストファイルを作成
- [ ] 3.2 既存 7 パターン（`_nudge_command_for_pattern` の全出力）が allow-list 正規表現を通過することを検証するテストケース追加
- [ ] 3.3 `check_and_nudge` に不正な `next_cmd` を注入した場合に `tmux send-keys` が呼ばれないことを確認するテストケース追加（モック方式）

## 4. 検証

- [ ] 4.1 `twl check` でプラグイン整合性を確認
- [ ] 4.2 shunit2 テストを実行してグリーンを確認
