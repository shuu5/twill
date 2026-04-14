## 1. スクリプト抽出

- [ ] 1.1 `plugins/twl/scripts/merge-gate-check-pr.sh` を作成し、PR 存在確認ロジック（L20-29）を移植する
- [ ] 1.2 `plugins/twl/scripts/merge-gate-build-manifest.sh` を作成し、動的レビュアー構築ロジック（L39-50）を移植する
- [ ] 1.3 `plugins/twl/scripts/merge-gate-check-spawn.sh` を作成し、spawn 完了確認ロジック（L79-91）を移植する
- [ ] 1.4 `plugins/twl/scripts/merge-gate-cross-pr-ac.sh` を作成し、Cross-PR AC 検証ロジック（L118-129）を移植する
- [ ] 1.5 `plugins/twl/scripts/merge-gate-checkpoint-merge.sh` を作成し、checkpoint 統合ロジック（L136-140）を移植する
- [ ] 1.6 `plugins/twl/scripts/merge-gate-check-phase-review.sh` を作成し、phase-review 必須チェックロジック（L149-154）を移植する

## 2. merge-gate.md リファクタリング

- [ ] 2.1 `merge-gate.md` の各インライン bash ブロックをスクリプト呼び出し参照に置き換える
- [ ] 2.2 `merge-gate.md` の行数が 120 行以下であることを `wc -l` で確認する

## 3. 検証

- [ ] 3.1 各スクリプトに実行権限（`chmod +x`）を付与する
- [ ] 3.2 `twl check` を実行してプラグイン整合性を確認する
