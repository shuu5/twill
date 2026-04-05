## ADDED Requirements

### Requirement: ref-glossary-criteria.md の作成

`refs/ref-glossary-criteria.md` を新規作成し、glossary 用語登録判断の3軸基準・判定ロジック・MUST/SHOULD 振り分け基準・具体例を明文化しなければならない（SHALL）。

#### Scenario: 3軸基準が参照可能
- **WHEN** Step 1.5 で LLM が未登録用語を評価するとき
- **THEN** ref-glossary-criteria.md を Read することで3軸基準・判定ロジック・具体例を参照できる

#### Scenario: 具体例で判断精度を担保
- **WHEN** 用語が「登録推奨」か「登録不要」か境界が曖昧なとき
- **THEN** ref-glossary-criteria.md の具体例セクションを参照して判断方針を統一できる

### Requirement: deps.yaml への ref-glossary-criteria エントリ追加

`deps.yaml` の `refs:` セクションに `ref-glossary-criteria` エントリを追加し、`co-issue.calls` に `reference: ref-glossary-criteria` を追加しなければならない（SHALL）。

#### Scenario: loom check が PASS する
- **WHEN** `loom check` を実行するとき
- **THEN** ref-glossary-criteria エントリが適切に登録されており PASS する

## MODIFIED Requirements

### Requirement: Step 1.5 への LLM 分類フロー追加

`skills/co-issue/SKILL.md` の Step 1.5 を拡張し、INFO 通知後に以下のフローを追加しなければならない（SHALL）:
1. `refs/ref-glossary-criteria.md` を DCI で Read する
2. 各未登録用語を3軸（Context 横断性・ドメイン固有性・定着度）で評価する
3. 2軸以上で「登録すべき」に該当する用語を登録推奨候補としてテーブル表示し、AskUserQuestion で確認する
4. ユーザーが承認した用語の glossary.md 追記テキストを提示する（Edit による自動書き込みは禁止）

#### Scenario: 登録推奨用語がある場合
- **WHEN** 未登録用語のうち2軸以上で「登録すべき」に該当する用語が1件以上存在するとき
- **THEN** テーブル（用語・定義案・Context・MUST/SHOULD・判断理由）を表示し AskUserQuestion でユーザー確認を求める

#### Scenario: 登録推奨用語がない場合
- **WHEN** 全未登録用語が1軸以下（登録不要判定）のとき
- **THEN** AskUserQuestion なしで Phase 2 に継続する

#### Scenario: ユーザーが全拒否した場合
- **WHEN** ユーザーが提案された全用語を拒否するとき
- **THEN** glossary.md は変更せず Phase 2 に継続する（非ブロッキング）

### Requirement: context-map.md 不在時のフォールバック明記

Step 1.5 に context-map.md が ARCH_CONTEXT に含まれない場合のフォールバック処理を明記しなければならない（SHALL）: Context 横断性を「不明」として1軸分マイナス扱い（残り2軸のうち2軸以上で推奨）とする。

#### Scenario: context-map.md がない場合
- **WHEN** ARCH_CONTEXT に context-map.md が含まれないとき
- **THEN** Context 横断性の評価を「不明」とし、ドメイン固有性・定着度の2軸が両方「登録すべき」の場合のみ登録推奨とする
