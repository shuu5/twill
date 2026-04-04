## 1. chain-runner.sh quick-guard コマンド追加

- [x] 1.1 `scripts/chain-runner.sh` に `step_quick_guard()` 関数を追加（state 優先 → detect_quick_label() fallback → exit 1/0）
- [x] 1.2 ブランチから Issue 番号が抽出できない場合は exit 0 を返すよう実装
- [x] 1.3 `case` ディスパッチに `quick-guard` エントリを追加

## 2. workflow-test-ready/SKILL.md quick ガード追加

- [x] 2.1 Step 1 の前に「Quick Guard」セクションを追加
- [x] 2.2 `bash scripts/chain-runner.sh quick-guard || { echo "quick Issue のため test-ready をスキップします"; exit 0; }` を挿入

## 3. deps.yaml 更新

- [x] 3.1 `chain-runner.sh` コンポーネントの `commands` フィールドに `quick-guard` を追記

## 4. 検証

- [x] 4.1 `loom check` を実行してエラーがないことを確認
- [x] 4.2 `loom update-readme` を実行
