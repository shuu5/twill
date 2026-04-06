## 1. キーワード検証ヘルパー追加

- [x] 1.1 `REQUIRED_OUTPUT_KEYWORDS` 定数を定義（result_values, structure, severity, confidence）
- [x] 1.2 `_check_output_schema_keywords(file_path)` 関数を追加（カテゴリ別の合否判定を返す）

## 2. deep-validate チェック (D) 追加

- [x] 2.1 `deep_validate()` に `(D) Specialist 出力スキーマ検証` セクションを追加
- [x] 2.2 `output_schema: custom` スキップ処理を実装
- [x] 2.3 `output_schema` 不正値の WARNING を実装

## 3. audit Section 5 拡張

- [x] 3.1 Section 5 テーブルに Schema 列を追加
- [x] 3.2 Schema 列の値（Yes/No/Skip）を出力
- [x] 3.3 severity 判定に Schema 不足を反映（WARNING）

## 4. テスト追加

- [x] 4.1 `_check_output_schema_keywords` のユニットテスト
- [x] 4.2 deep-validate specialist-output-schema のシナリオテスト（全キーワード合格、不足、PASS/FAIL片方のみ）
- [x] 4.3 output_schema custom スキップのテスト
- [x] 4.4 output_schema 不正値 WARNING のテスト
- [x] 4.5 audit Section 5 Schema 列のテスト
- [x] 4.6 既存テストの通過確認
