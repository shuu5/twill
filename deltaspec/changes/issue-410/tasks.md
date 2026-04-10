## 1. test-common.sh 作成

- [ ] 1.1 `plugins/twl/tests/helpers/` ディレクトリを作成する
- [ ] 1.2 `tests/helpers/test-common.sh` を作成し、`assert_file_exists`, `assert_file_contains`, `assert_file_not_contains`, `run_test`, `run_test_skip` 関数を移植する
- [ ] 1.3 カウンター初期化（`PASS=0`, `FAIL=0`, `SKIP=0`, `ERRORS=()`）を `test-common.sh` に追加する
- [ ] 1.4 `print_summary()` 関数を `test-common.sh` に追加し、サマリー出力と `exit $FAIL` を担当させる

## 2. skillmd-pilot-fixes.test.sh リファクタリング

- [ ] 2.1 `skillmd-pilot-fixes.test.sh` の先頭でヘルパー関数・カウンター初期化を `source` に置き換える（`BASH_SOURCE[0]` を使った絶対パス解決）
- [ ] 2.2 末尾のサマリー出力ブロックを `print_summary` 呼び出しに置き換える
- [ ] 2.3 `wc -l` でスクリプトが 300 行以下であることを確認する

## 3. 検証

- [ ] 3.1 リファクタリング後の `skillmd-pilot-fixes.test.sh` を実行し、テスト結果が変わらないことを確認する
