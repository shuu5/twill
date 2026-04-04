## ADDED Requirements

### Requirement: glossary.md 機械的ガード

`architecture/domain/glossary.md` への Edit/Write を PreToolUse フックで自動ブロックしなければならない（SHALL）。

#### Scenario: Edit で glossary.md を変更しようとした場合
- **WHEN** Claude が `Edit` ツールで `architecture/domain/glossary.md` に対して呼び出しを行う
- **THEN** PreToolUse フックが exit 2 で終了し、「glossary.md の変更は /dev:co-architect 経由で行ってください」というメッセージが表示されてブロックされる

#### Scenario: Write で glossary.md を上書きしようとした場合
- **WHEN** Claude が `Write` ツールで `architecture/domain/glossary.md` に対して呼び出しを行う
- **THEN** PreToolUse フックが exit 2 で終了し、操作がブロックされる

#### Scenario: 他のファイルへの Edit/Write は影響しない
- **WHEN** Claude が `Edit` ツールで `glossary.md` 以外のファイルに対して呼び出しを行う
- **THEN** フックは exit 0 で終了し、操作は正常に継続される

## MODIFIED Requirements

### Requirement: Step 1.5 ステップ3の照合方向明確化

co-issue SKILL.md の Step 1.5 ステップ3は、「explore-summary から抽出した用語を glossary MUST 用語テーブルに照合する」方向を明示しなければならない（SHALL）。

#### Scenario: ステップ3の実行
- **WHEN** Step 1.5 が実行され、ステップ3で未登録用語を照合する
- **THEN** explore-summary.md から抽出した用語のうち、MUST 用語テーブルに存在しない用語のみが列挙される（explore-summary → glossary の照合方向）
