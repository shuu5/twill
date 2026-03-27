## 1. Template B --write 完全実装

- [x] 1.1 `chain_generate_write()` の Template B 処理（行3120-3138）を書き込みロジックに置換: frontmatter description 行の検出 → called-by パターンの正規表現マッチ → 置換または追記
- [x] 1.2 called-by パターン正規表現 `。\S+ (?:Step \d+ )?から呼び出される。` を定数として定義
- [x] 1.3 description 行が存在しない場合の Warning + スキップ処理

## 2. Template B --check ドリフト検出

- [x] 2.1 `_extract_called_by()` ヘルパー関数を追加: frontmatter description から called-by 部分を抽出
- [x] 2.2 `chain_generate_check()` に Template B の検証ロジックを追加: 期待値と実際の called-by 文を比較し DRIFT/ok を判定
- [x] 2.3 Template A と Template B の結果を統合して返却

## 3. テスト

- [x] 3.1 Template B --write の新規追記テスト
- [x] 3.2 Template B --write の既存 called-by 更新テスト
- [x] 3.3 Template B --write の description 保持テスト
- [x] 3.4 Template B --check のドリフト検出テスト（一致 / 不一致 / 欠落）
- [x] 3.5 既存テストが全て通ることを確認
