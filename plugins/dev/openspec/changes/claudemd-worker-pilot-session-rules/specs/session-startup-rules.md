## MODIFIED Requirements

### Requirement: Bare repo 構造検証を Pilot セッション専用として明示

CLAUDE.md の「Bare repo 構造検証（セッション開始時チェック）」セクションは Pilot セッション専用のルールであることを明示しなければならない（SHALL）。Worker セッションは worktree ディレクトリで起動されるため、このチェックの適用対象外であることを注記として含めなければならない（SHALL）。

#### Scenario: Pilot セッション起動チェック
- **WHEN** CLAUDE.md を参照したセッションが Pilot（main/ で動作）である
- **THEN** 「Bare repo 構造検証」の3条件（.bare/ 存在、main/.git ファイル、CWD が main/ 配下）が Pilot 向けチェックとして正しく認識される

#### Scenario: Worker セッションの適用除外
- **WHEN** CLAUDE.md を参照したセッションが Worker（worktree 内で動作）である
- **THEN** 「Bare repo 構造検証」が Worker には適用されない旨が CLAUDE.md の注記から読み取れる

### Requirement: セッション起動ルールを Pilot/Worker 別に記述

CLAUDE.md の「セッション起動ルール」セクションは Pilot と Worker を区別して記述しなければならない（SHALL）。Pilot のルール（main/ で起動）と Worker のルール（Pilot が作成した worktree 内で起動）が明確に分離されていなければならない（SHALL）。

#### Scenario: Pilot 起動ルール参照
- **WHEN** CLAUDE.md「セッション起動ルール」を参照する
- **THEN** Pilot は main/ で起動することが明記されており、worktree 削除による bash CWD 消失リスクの説明が保持されている

#### Scenario: Worker 起動ルール参照
- **WHEN** CLAUDE.md「セッション起動ルール」を参照する
- **THEN** Worker は Pilot が事前作成した worktrees/<branch>/ 内で起動することが明記されており、ADR-008 への準拠が確認できる

## ADDED Requirements

### Requirement: Worker セッション向けルールの新規追記

CLAUDE.md に Worker セッションが worktree 内で起動されることを明記するルールを追加しなければならない（SHALL）。このルールは ADR-008（Worktree Lifecycle Pilot Ownership）に準拠していなければならない（SHALL）。

#### Scenario: Worker 向けルールの存在確認
- **WHEN** CLAUDE.md の「セッション起動ルール」セクションを読む
- **THEN** Worker セッションが worktrees/<branch>/ 内で起動されるという記述が存在する
