## 1. find_deltaspec_root エラーメッセージ強化（AC-2）

- [x] 1.1 `cli/twl/src/twl/spec/paths.py` の `DeltaspecNotFound` raise 箇所を修正し、walk-up 開始パス・git top・rebase 推奨 hint を含むメッセージに更新する

## 2. auto-init 抑制ガード実装（AC-1）

- [x] 2.1 `cli/twl/src/twl/spec/new.py` の `except DeltaspecNotFound` ブロックで `git ls-tree origin/main --name-only` を実行し、nested `deltaspec/config.yaml` の存在を確認するロジックを追加する
- [x] 2.2 nested root が検出された場合（かつ `TWL_SPEC_ALLOW_AUTO_INIT` 未設定）: エラーメッセージ出力 + exit code 1 で early return する
- [x] 2.3 `git ls-tree` 失敗時（offline 等）: WARN 出力 + 従来の auto-init フォールバックを実装する
- [x] 2.4 `TWL_SPEC_ALLOW_AUTO_INIT=1` 設定時: 従来の auto-init フローに進むよう分岐を追加する

## 3. chain-runner step_init rebase ガード（AC-3）

- [x] 3.1 `plugins/twl/scripts/chain-runner.sh` の `step_init` 関数に `_check_nested_deltaspec_configs()` ヘルパーを追加する（plugins/twl と cli/twl の config.yaml 存在チェック）
- [x] 3.2 欠落ファイルごとに `warn` ログを出力し、`git rebase origin/main` を推奨するメッセージを出す
- [x] 3.3 ガード失敗でも `step_init` フロー自体は abort しないことを確認する

## 4. change-propose.md auto_init 条件の文言更新

- [x] 4.1 `plugins/twl/commands/change-propose.md` の Step 0 auto_init 条件説明を `DELTASPEC_EXISTS=false` から「cwd から有効な nested deltaspec root が参照できない」に更新し、誤解を防ぐ

## 5. テスト追加（AC-6）

- [x] 5.1 `cli/twl/tests/spec/test_new.py` に `test_new_auto_init_suppressed_when_nested_root_exists` を追加（`git ls-tree` をモック）
- [x] 5.2 `cli/twl/tests/spec/test_new.py` に `test_new_auto_init_allowed_with_env_var` を追加
- [x] 5.3 `cli/twl/tests/spec/test_new.py` に `test_new_auto_init_fallback_when_git_ls_tree_fails` を追加（offline フォールバック）
- [x] 5.4 bats scenario を追加: `test-fixtures/` または既存の bats テストディレクトリに「pre-#435 branch で `twl spec new` が早期失敗する」シナリオを作成する

## 6. 検証

- [x] 6.1 `pytest cli/twl/tests/spec/test_new.py` で新規テストが通ることを確認する
- [x] 6.2 手動で `TWL_SPEC_ALLOW_AUTO_INIT=1 twl spec new test-xxx` が auto-init することを確認する
- [x] 6.3 `TWL_SPEC_ALLOW_AUTO_INIT` 未設定で deltaspec root 外から `twl spec new` を実行すると適切なエラーメッセージが出ることを確認する
