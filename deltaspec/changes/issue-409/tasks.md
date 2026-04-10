## 1. smoke test スクリプト作成

- [ ] 1.1 `plugins/twl/tests/scenarios/co-autopilot-smoke.test.sh` を新規作成する
- [ ] 1.2 テストヘルパー（`run_test`, `run_test_skip`, PASS/FAIL/SKIP カウンタ）を既存テストと同形式で実装する
- [ ] 1.3 `python-env.sh` を source して PYTHONPATH を設定するセットアップ処理を追加する

## 2. state write/read テスト実装

- [ ] 2.1 一時ディレクトリを作成・クリーンアップする `setup_tmpdir` / `teardown` 処理を実装する
- [ ] 2.2 `python3 -m twl.autopilot.state write` + `read` の基本動作テストを実装する
- [ ] 2.3 `python3 -m twl.autopilot.state` が import エラーの場合 SKIP するガードを追加する

## 3. plan.yaml 生成テスト実装

- [ ] 3.1 `gh` コマンドの認証状態を確認し、未認証なら SKIP するガードを実装する
- [ ] 3.2 `autopilot-plan.sh --explicit` を一時ディレクトリで実行し `plan.yaml` 生成を検証するテストを実装する

## 4. テスト実行確認

- [ ] 4.1 smoke test を手動実行してすべての PASS/SKIP が正しく動作することを確認する
- [ ] 4.2 既存の `skillmd-pilot-fixes.test.sh` が引き続き PASS することを確認する
