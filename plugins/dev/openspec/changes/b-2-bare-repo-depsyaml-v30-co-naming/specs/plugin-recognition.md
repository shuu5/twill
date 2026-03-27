## ADDED Requirements

### Requirement: plugin.json によるプラグイン認識

`.claude-plugin/plugin.json` を配置し、Claude Code がこのリポジトリを dev plugin として認識できるようにする（SHALL）。

plugin.json は以下のフィールドを含まなければならない（MUST）:
- `name`: プラグイン名 ("dev")
- `version`: バージョン文字列
- `description`: プラグイン説明

#### Scenario: Claude Code がプラグインを認識する
- **WHEN** Claude Code が `main/` ディレクトリでセッションを開始する
- **THEN** `.claude-plugin/plugin.json` が存在し、正しい JSON として読み込める

#### Scenario: plugin.json の必須フィールド検証
- **WHEN** `.claude-plugin/plugin.json` を読み込む
- **THEN** `name`, `version`, `description` の3フィールドが全て存在する

### Requirement: プラグインディレクトリ構造

skills/, commands/, agents/, refs/, scripts/ ディレクトリが存在しなければならない（MUST）。controller 4つ分の SKILL.md が skills/ 配下に配置されなければならない（SHALL）。

#### Scenario: ディレクトリ構造の完備
- **WHEN** `main/` のディレクトリ構造を検査する
- **THEN** 以下のディレクトリが全て存在する: `skills/`, `commands/`, `agents/`, `refs/`, `scripts/`

#### Scenario: controller ディレクトリの存在
- **WHEN** `skills/` 配下を検査する
- **THEN** `co-autopilot/`, `co-issue/`, `co-project/`, `co-architect/` の4ディレクトリが存在し、各ディレクトリに `SKILL.md` が配置されている
