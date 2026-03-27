## 1. 引数パース拡張

- [x] 1.1 `handle_chain_subcommand()` の argparse を変更: `chain_name` を `nargs='?'` に、`--check` と `--all` フラグ追加
- [x] 1.2 排他バリデーション実装: `--all` と `chain_name` 同時指定エラー、`--check` と `--write` 同時指定エラー、引数なしエラー

## 2. --check コア実装

- [x] 2.1 `_normalize_for_check()` 関数追加: trailing whitespace 除去 + LF 統一
- [x] 2.2 `_extract_checkpoint_section()` 関数追加: ファイルからチェックポイントセクション抽出（既存正規表現流用）
- [x] 2.3 `chain_generate_check()` 関数追加: 単一 chain の Template A ドリフト検出（正規化ハッシュ比較 + unified diff）

## 3. --all 実装

- [x] 3.1 `handle_chain_subcommand()` に `--all` 分岐追加: 全 chain 反復処理（stdout / --write / --check）
- [x] 3.2 `--all --check` のサマリー出力形式実装: ファイルレベルサマリー + 末尾 diff + 全体サマリー

## 4. テスト

- [x] 4.1 `tests/test_chain_generate_check.py` 新規作成: --check の正規化・ドリフト検出・セクション不在・排他制御テスト
- [x] 4.2 `tests/test_chain_generate_all.py` 新規作成: --all の一括操作・0件・排他制御・サマリー出力テスト
- [x] 4.3 既存テスト通過確認: `pytest tests/` で全テスト pass
