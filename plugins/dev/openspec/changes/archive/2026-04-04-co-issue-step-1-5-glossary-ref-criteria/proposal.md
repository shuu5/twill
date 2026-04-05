## Why

co-issue の Step 1.5 は未登録の glossary 用語を INFO 通知するだけで、登録すべきかどうかの判断基準が暗黙知のままユーザーに毎回委ねられている。登録判断の3軸基準を `ref-glossary-criteria.md` として明文化し、LLM が自動分類して登録候補のみをユーザーに提案することで、判断コストを削減する。

## What Changes

- `refs/ref-glossary-criteria.md` を新規作成（3軸基準・判定ロジック・MUST/SHOULD 振り分け・具体例）
- `skills/co-issue/SKILL.md` の Step 1.5 を拡張（INFO 通知後に ref-glossary-criteria を Read し、LLM が各用語を3軸判断→登録候補をユーザー提案するフローを追加）
- `deps.yaml` に ref-glossary-criteria エントリと co-issue.calls 参照を追加

## Capabilities

### New Capabilities

- **glossary 登録判断基準の明文化**: 3軸（Context 横断性・ドメイン固有性・定着度）のうち2軸以上で「登録すべき」に該当する場合に登録推奨。1軸のみは登録不要
- **LLM 自動分類フロー**: Step 1.5 で未登録用語ごとに3軸判断を行い、登録推奨用語のみをテーブル表示してユーザーに確認を求める
- **MUST/SHOULD 振り分け**: Context 横断性あり→MUST、なし→SHOULD として提案

### Modified Capabilities

- **Step 1.5 INFO 通知**: 単なる通知から「分類済み登録提案」に格上げ。ユーザー確認後に glossary.md 追記テキストを提示（自動書き込みなし）
- **非ブロッキング原則の維持**: 全拒否でも Phase 2 に継続

## Impact

- `refs/ref-glossary-criteria.md`: 新規ファイル
- `skills/co-issue/SKILL.md`: Step 1.5 セクション拡張（Step 4 以降を追加）
- `deps.yaml`: refs セクション + co-issue.calls セクションにエントリ追加
- `loom check` が PASS すること
