## 1. Reference コンポーネント作成

- [x] 1.1 `refs/ref-specialist-output-schema.md` 作成（JSON Schema + severity/status 定義 + 消費側パースルール + model 割り当て表）
- [x] 1.2 `refs/ref-specialist-few-shot.md` 作成（FAIL ケース 1 例テンプレート + 注入セクション形式）

## 2. deps.yaml 更新

- [x] 2.1 deps.yaml に `refs` セクション追加（ref-specialist-output-schema, ref-specialist-few-shot）
- [x] 2.2 `output_schema: custom` の除外条件を ref-specialist-output-schema に記載

## 3. 検証

- [x] 3.1 `loom check` pass 確認
- [x] 3.2 `loom validate` 新規 violation 0 件確認
- [x] 3.3 `loom update-readme` 実行（README.md 未存在のため N/A）
