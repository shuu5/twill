## 1. 共通基盤

- [x] 1.1 argparse に `--format` 引数を追加（choices=['json']）
- [x] 1.2 `build_envelope()` 関数を実装（command, version, plugin, items, summary, exit_code）
- [x] 1.3 `output_json()` ヘルパーを実装（envelope を stdout に json.dumps）

## 2. Phase 1: validate の JSON 対応

- [x] 2.1 validate_types() の violations を構造化（code, component, message をパース可能にする）
- [x] 2.2 validate_body_refs() の結果を items 形式に変換するロジック追加
- [x] 2.3 validate_v3_schema() の結果を items 形式に変換するロジック追加
- [x] 2.4 chain_validate() の結果を items 形式に変換するロジック追加
- [x] 2.5 `--validate --format json` のディスパッチ実装（main 関数内）
- [x] 2.6 validate JSON 出力のテスト追加

## 3. Phase 1: deep-validate の JSON 対応

- [x] 3.1 deep_validate() の criticals/warnings/infos を items 形式に変換するロジック追加
- [x] 3.2 `--deep-validate --format json` のディスパッチ実装
- [x] 3.3 deep-validate JSON 出力のテスト追加

## 4. Phase 1: check の JSON 対応

- [x] 4.1 check_files() の results を items 形式に変換するロジック追加
- [x] 4.2 chain_validate 結果との統合（v3.0 時）
- [x] 4.3 `--check --format json` のディスパッチ実装
- [x] 4.4 check JSON 出力のテスト追加

## 5. Phase 2: audit のリファクタ + JSON 対応

- [x] 5.1 audit_collect() 関数を新設（print() なし、items リストを return）
- [x] 5.2 audit_report() を audit_collect() のラッパーに変更（後方互換維持）
- [x] 5.3 `--audit --format json` のディスパッチ実装
- [x] 5.4 audit テキスト出力の後方互換テスト
- [x] 5.5 audit JSON 出力のテスト追加

## 6. Phase 2: complexity のリファクタ + JSON 対応

- [x] 6.1 complexity_collect() 関数を新設（print() なし、items リストを return）
- [x] 6.2 complexity_report() を complexity_collect() のラッパーに変更（後方互換維持）
- [x] 6.3 `--complexity --format json` のディスパッチ実装
- [x] 6.4 complexity テキスト出力の後方互換テスト
- [x] 6.5 complexity JSON 出力のテスト追加

## 7. 統合テスト

- [x] 7.1 全コマンドの `--format json` が共通エンベロープを満たすことの統合テスト
- [x] 7.2 既存テストが全て通ることの確認
