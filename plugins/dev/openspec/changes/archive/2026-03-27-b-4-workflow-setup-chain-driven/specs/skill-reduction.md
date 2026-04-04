## MODIFIED Requirements

### Requirement: workflow-setup SKILL.md トークン削減

workflow-setup の SKILL.md を現行比 50% 以上のトークン削減を達成しなければならない（SHALL）。chain で表現可能なステップ順序・条件分岐ルーティングを削除し、ドメインルールのみを残す（MUST）。

#### Scenario: トークン削減率の達成
- **WHEN** 新しい SKILL.md のトークン数を測定する
- **THEN** 旧 plugin の workflow-setup SKILL.md 比で 50% 以上のトークン削減が達成されている

#### Scenario: chain ステップの記述が排除されている
- **WHEN** SKILL.md の内容を確認する
- **THEN** 「Step N: xxx を Skill tool で実行」形式の手順記述が存在しない（chain generate のチェックポイントテンプレートに委譲）

### Requirement: SKILL.md に残すドメインルール

SKILL.md には chain で表現できない以下のドメインルールのみを記載しなければならない（SHALL）。

1. arch-ref コンテキスト抽出ロジック（`<!-- arch-ref-start -->` タグ解析）
2. OpenSpec 分岐条件（propose/apply/direct の判定ルール）
3. 引数解析ルール（`--auto`, `--auto-merge`, `#N`）

上記以外の手続き的記述は SKILL.md に含めてはならない（MUST）。

#### Scenario: arch-ref 抽出ルールが記載されている
- **WHEN** SKILL.md を確認する
- **THEN** Issue body/comments からの `<!-- arch-ref-start -->` タグ解析、最大 5 件の architecture/ ファイル読み取り、`..` パス拒否のルールが記載されている

#### Scenario: 手続き的記述が排除されている
- **WHEN** SKILL.md を確認する
- **THEN** 「bash $SCRIPTS_ROOT/xxx.sh」「gh issue view」「gh project item-add」等の具体的コマンド記述が存在しない（各 COMMAND.md に委譲）
