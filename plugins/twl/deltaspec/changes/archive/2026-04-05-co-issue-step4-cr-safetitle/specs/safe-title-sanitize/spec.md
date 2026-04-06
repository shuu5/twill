## MODIFIED Requirements

### Requirement: SAFE_TITLE を allow-list 方式でサニタイズする

co-issue Step 4-CR は、GitHub Issue タイトルを `gh issue create --title` に渡す前に SAFE_TITLE を生成しなければならない（SHALL）。SAFE_TITLE は `LC_ALL=C tr -cd '[:alnum:][:space:]._-'` により ASCII 英数字・スペース・ピリオド・アンダースコア・ハイフン以外の文字を除去しなければならない（MUST）。

#### Scenario: バッククォートを含むタイトルのサニタイズ
- **WHEN** TITLE に バッククォート（`` ` ``）が含まれる
- **THEN** SAFE_TITLE にバッククォートが含まれない

#### Scenario: `$` を含むタイトルのサニタイズ
- **WHEN** TITLE に `$` が含まれる
- **THEN** SAFE_TITLE に `$` が含まれない

#### Scenario: `!` を含むタイトルのサニタイズ
- **WHEN** TITLE に `!`（bash history expansion）が含まれる
- **THEN** SAFE_TITLE に `!` が含まれない

#### Scenario: ASCII 英数字・許可文字の保持
- **WHEN** TITLE が `[Feature] add-user auth.v2` の形式
- **THEN** SAFE_TITLE は `Feature add-user auth.v2` となる（`[` `]` は除去、英数字・スペース・ハイフン・ピリオドは保持）

### Requirement: セキュリティ注意セクションを allow-list 方式に更新する

co-issue SKILL.md のセキュリティ注意セクション（Step 4-CR）は、SAFE_TITLE が allow-list 方式で生成される旨を説明しなければならない（SHALL）。deny-list 方式の説明を残してはならない（MUST NOT）。

#### Scenario: セクション説明の更新確認
- **WHEN** SKILL.md Step 4-CR のセキュリティ注意セクションを参照する
- **THEN** 説明文に allow-list 方式（`LC_ALL=C tr -cd '[:alnum:][:space:]._-'`）の記述がある
