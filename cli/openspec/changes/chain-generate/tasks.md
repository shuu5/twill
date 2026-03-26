## 1. CLI サブコマンド基盤

- [x] 1.1 `sys.argv` 前処理で `chain generate` サブコマンドを検出し、専用の argparse パーサーに分岐する処理を `main()` 関数に追加
- [x] 1.2 `chain generate` 用の argparse パーサーを定義（positional: chain-name、optional: --write）
- [x] 1.3 v3.0 バージョンチェック（3.x 未満でエラー終了）
- [x] 1.4 chain-name 存在チェック（chains セクションに未定義でエラー終了）

## 2. テンプレート生成関数

- [x] 2.1 `chain_generate(deps, chain_name, plugin_root)` メイン関数を実装（Template A/B/C を辞書で返す）
- [x] 2.2 Template A 生成: chains.steps から position+1 の next コンポーネントを解決し、チェックポイント出力テンプレートを生成
- [x] 2.3 Template B 生成: step_in を持つコンポーネントの called-by 宣言行を生成（step フィールド有無で分岐）
- [x] 2.4 Template C 生成: chains.steps と各コンポーネントの type/description からライフサイクル図テーブルを生成

## 3. stdout 出力

- [x] 3.1 Template A/B/C をセクション区切り付きで stdout に出力する関数を実装
- [x] 3.2 chain type による出力分岐（Chain A: Template A + C、Chain B: Template B、未指定: 全テンプレート）

## 4. --write 機能

- [x] 4.1 プロンプトファイル内のセクション検出パターンを実装（チェックポイント/Checkpoint、ライフサイクル/Lifecycle）
- [x] 4.2 frontmatter description 内の called-by パターン検出を実装
- [x] 4.3 検出セクションの置換処理を実装（マーカー未検出時は警告+スキップ）
- [x] 4.4 path フィールド未設定コンポーネントのスキップ処理

## 5. テスト

- [x] 5.1 Template A/B/C の生成結果を検証するユニットテスト
- [x] 5.2 --write のセクション検出・置換を検証するテスト
- [x] 5.3 エラーケース（v2.0、存在しない chain 名）のテスト
