## MODIFIED Requirements

### Requirement: workflow-pr-merge/SKILL.md に不変条件 C 禁止を明記

Worker が workflow-pr-merge/SKILL.md を参照した際に、`gh pr merge` 直接実行が禁止されていることを明確に認識できなければならない（SHALL）。禁止事項セクションに不変条件 C として「Worker は `gh pr merge` を直接実行してはならない。マージは必ず `chain-runner.sh auto-merge` 経由で auto-merge.sh のガードを通すこと」が明記されていなければならない（MUST）。

#### Scenario: Worker が workflow-pr-merge を参照する
- **WHEN** Worker が workflow-pr-merge/SKILL.md の禁止事項セクションを読む
- **THEN** 「Worker は `gh pr merge` を直接実行してはならない（不変条件 C）」という禁止文が明記されている

#### Scenario: 不変条件 C と E, F が同一セクションに存在する
- **WHEN** 禁止事項セクションを確認する
- **THEN** 不変条件 C（マージ禁止）、E（リトライ）、F（rebase 禁止）が全て記載されている

### Requirement: autopilot-launch.sh の Worker 起動コンテキストに merge 禁止を注入

autopilot-launch.sh が Worker を起動する際、`gh pr merge` 直接実行を禁止する固定テキストをシステムプロンプトとして注入しなければならない（MUST）。注入は quick ラベル注入と同一パターン（`CONTEXT` 変数への追記）を使用し、全 Issue で常時注入されなければならない（SHALL）。

#### Scenario: Worker 起動時に merge 禁止コンテキストが注入される
- **WHEN** autopilot-launch.sh が Worker（Claude Code）を起動する
- **THEN** `--append-system-prompt` に「`gh pr merge` の直接実行は禁止。マージ権限は Pilot のみ（不変条件 C）」というテキストが含まれている

#### Scenario: quick ラベルと同時に適用される
- **WHEN** quick ラベル付き Issue で Worker を起動する
- **THEN** merge 禁止コンテキストと quick 指示の両方がシステムプロンプトに注入される

### Requirement: co-autopilot/SKILL.md の不変条件 C に enforcement 参照を追記

co-autopilot/SKILL.md の不変条件一覧（不変条件 C の記述）に、enforcement が定義されているファイルへの参照リンクが含まれていなければならない（SHALL）。内容の詳細展開は不要で、ファイルパスの参照のみで良い（MUST）。

#### Scenario: Pilot が不変条件 C の enforcement 箇所を確認する
- **WHEN** co-autopilot/SKILL.md の不変条件セクションを参照する
- **THEN** 不変条件 C の記述に「enforcement: workflow-pr-merge/SKILL.md 禁止事項セクション + autopilot-launch.sh 起動コンテキスト参照」が含まれている

### Requirement: auto-merge.sh の既存ガードを維持

auto-merge.sh の 4-layer ガード（IS_AUTOPILOT チェック等）は変更されてはならない（MUST NOT）。

#### Scenario: auto-merge.sh のガードが正常に動作する
- **WHEN** auto-merge.sh が IS_AUTOPILOT=true で実行される
- **THEN** merge-ready 宣言のみ行い、`gh pr merge` は実行しない（既存動作）
