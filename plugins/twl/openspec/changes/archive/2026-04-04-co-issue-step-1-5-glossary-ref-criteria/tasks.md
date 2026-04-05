## 1. ref-glossary-criteria.md の作成

- [x] 1.1 `refs/ref-glossary-criteria.md` を新規作成し、3軸基準テーブルを記載する（Context 横断性・ドメイン固有性・定着度）
- [x] 1.2 判定ロジック（2/3軸以上で登録推奨、1軸以下で登録不要）を記載する
- [x] 1.3 MUST/SHOULD 振り分け基準（Context 横断性あり→MUST、なし→SHOULD）を記載する
- [x] 1.4 具体例セクションを追加する（findings→登録推奨、maxTurns/scope_files→登録不要 等）

## 2. skills/co-issue/SKILL.md の Step 1.5 拡張

- [x] 2.1 Step 1.5 の既存ステップ4（INFO 通知）の後に、ref-glossary-criteria を DCI で Read するステップ5を追加する
- [x] 2.2 各未登録用語を3軸判断するステップ6を追加する（context-map.md 不在時のフォールバック明記含む）
- [x] 2.3 2軸以上該当の用語をテーブル表示し AskUserQuestion で確認するステップ7を追加する
- [x] 2.4 登録推奨なし or 全拒否時の Phase 2 継続（非ブロッキング）をステップ8として明記する

## 3. deps.yaml の更新

- [x] 3.1 `deps.yaml` の `refs:` セクションに `ref-glossary-criteria` エントリを追加する（type: reference、path、description 含む）
- [x] 3.2 `deps.yaml` の `co-issue.calls` に `reference: ref-glossary-criteria` を追加する

## 4. 検証

- [x] 4.1 `loom check` を実行して PASS を確認する
- [x] 4.2 `loom update-readme` を実行してドキュメントを更新する
