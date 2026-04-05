## ADDED Requirements

### Requirement: SKILL.MD 再生成

loom chain generate --write --all を実行し、全 SKILL.md を chain 定義から再生成しなければならない（SHALL）。Template C（loom#45）による starter 指示が各 SKILL.md に注入されることを確認する。

#### Scenario: 全 SKILL.md の再生成
- **WHEN** loom chain generate --write --all を loom-plugin-dev worktree 内で実行する
- **THEN** 全ての chain 定義を持つスキルの SKILL.md が更新され、Template C の starter 指示セクションが含まれる

#### Scenario: 再生成後の整合性
- **WHEN** SKILL.md 再生成が完了した後に loom check を実行する
- **THEN** chain 関連の整合性エラーが 0 件である
