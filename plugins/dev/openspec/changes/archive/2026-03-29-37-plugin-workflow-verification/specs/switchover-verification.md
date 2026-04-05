## ADDED Requirements

### Requirement: Switchover による検証環境構築

switchover.sh check → switch --new で symlink を loom-plugin-dev に切替え、検証環境を構築しなければならない（MUST）。検証完了後は rollback で旧プラグインに復元する。

#### Scenario: 事前チェックの成功
- **WHEN** switchover.sh check を loom-plugin-dev worktree 内で実行する
- **THEN** loom validate と loom check が全て OK となり、切替準備完了と判定される

#### Scenario: symlink 切替の実行
- **WHEN** switchover.sh switch --new で loom-plugin-dev のパスを指定する
- **THEN** ~/.claude/plugins/dev が loom-plugin-dev を指す symlink に更新され、旧リンクが dev.bak にバックアップされる

#### Scenario: 検証後のロールバック
- **WHEN** 全検証シナリオ完了後に switchover.sh rollback を実行する
- **THEN** ~/.claude/plugins/dev が旧プラグイン（claude-plugin-dev）に復元される
