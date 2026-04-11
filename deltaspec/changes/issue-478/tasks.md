## 1. SKILL.md ドキュメント追加

- [x] 1.1 `plugins/twl/skills/co-autopilot/SKILL.md` の「不変条件」セクション直前に「state file 解決ルール」セクションを追加する
- [x] 1.2 セクションに `AUTOPILOT_DIR` のデフォルト値（`$PROJECT_ROOT/.autopilot`）、override 方法、`autopilot-init.sh` L9 への参照、Pilot→Worker spawn 時の env 継承経路（`autopilot-launch.sh` の `env AUTOPILOT_DIR=...`）を記載する

## 2. bats テスト追加

- [x] 2.1 `plugins/twl/tests/bats/scripts/autopilot-launch-autopilotdir.bats` を新規作成する
- [x] 2.2 `autopilot-launch.sh` が `--autopilot-dir` を受け取り、起動コマンドに `AUTOPILOT_DIR` を含める動作を検証するテストを追加する
- [x] 2.3 カスタム `AUTOPILOT_DIR` 設定時に state ファイルが指定パスへ書き込まれることを検証するテストを追加する
- [x] 2.4 `AUTOPILOT_DIR` 未設定時のデフォルトフォールバック（`$PROJECT_ROOT/.autopilot`）を検証するテストを追加する（`autopilotdir-state-split.bats` と重複しないよう注意）

## 3. 回帰テスト実行

- [x] 3.1 `bats plugins/twl/tests/bats/scripts/autopilotdir-state-split.bats` を実行し全件 PASS を確認する
- [x] 3.2 `bats plugins/twl/tests/bats/scripts/autopilot-launch-autopilotdir.bats` を実行し全件 PASS を確認する
