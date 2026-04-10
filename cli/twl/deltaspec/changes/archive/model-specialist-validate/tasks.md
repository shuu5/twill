## 1. ALLOWED_MODELS 定数定義

- [x] 1.1 twl-engine.py のモジュールレベルに `ALLOWED_MODELS = {"haiku", "sonnet", "opus"}` を追加

## 2. deep_validate に model-required ルール追加

- [x] 2.1 deep_validate 関数内に (D) Model Declaration セクションを追加
- [x] 2.2 全コンポーネントから specialist を抽出し model フィールドをチェック
- [x] 2.3 model 未宣言 → WARNING `[model-required] {name}: specialist で model 未宣言`
- [x] 2.4 model が ALLOWED_MODELS にない → INFO `[model-required] {name}: model '{value}' は許可リストにありません`
- [x] 2.5 model = "opus" → WARNING `[model-required] {name}: specialist に opus は推奨されません`

## 3. audit に Section 6: Model Declaration 追加

- [x] 3.1 audit_report 関数に Section 6 を追加（Section 5 の後、Summary の前）
- [x] 3.2 テーブルヘッダー: `| Name | Type | Model | Severity |`
- [x] 3.3 specialist ごとに model 値と severity を出力
- [x] 3.4 severity カウント（warnings, oks）を更新

## 4. テスト追加

- [x] 4.1 model 未宣言 specialist の WARNING テスト
- [x] 4.2 正常な model 宣言（sonnet/haiku）のテスト
- [x] 4.3 未知 model 値の INFO テスト
- [x] 4.4 opus 宣言の WARNING テスト
- [x] 4.5 specialist 以外の型が model チェック対象外であるテスト
- [x] 4.6 audit Section 6 の出力フォーマットテスト
- [x] 4.7 既存テストが全てパスすることを確認
