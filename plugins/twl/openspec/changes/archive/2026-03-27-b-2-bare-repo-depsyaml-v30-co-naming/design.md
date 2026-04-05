## Context

loom-plugin-dev は B-1 で architecture/ にアーキテクチャ設計書を完成させた。このリポジトリは既に bare repo + worktree 構造で運用されているが、Claude Code プラグインとしてのディレクトリ構造・deps.yaml・hook 設定がまだ存在しない。

現状:
- `.bare/` + `main/` + `worktrees/` の git 構造は確立済み
- architecture/, openspec/, tests/ が存在
- CLAUDE.md は基本的な内容のみ（設計哲学、構成概要、編集フロー）

依存状況:
- loom#31 (scripts セクション): OPEN — deps.yaml に scripts トップレベルセクションは loom 側対応待ち。B-2 では component 内 scripts 属性で対応
- loom#28 (rename 完全化): OPEN — co-* ディレクトリ名は手動で作成（rename コマンド不要、新規構築のため）

## Goals / Non-Goals

**Goals:**

- .claude-plugin/plugin.json を配置し Claude Code プラグインとして認識させる
- deps.yaml v3.0 skeleton を作成（controller 4つ + 最小限のコンポーネント定義）
- loom check / loom validate が pass する状態にする
- skills/, commands/, agents/, refs/, scripts/ ディレクトリ構造を作成
- CLAUDE.md に bare repo 検証ルールとセッション起動ルールを追記
- .gitignore を配置
- hooks.json + PostToolUse hook を配置（loom validate on Edit/Write, Bash エラー記録）

**Non-Goals:**

- 個別コンポーネントの SKILL.md / コマンド .md の中身の実装（C-1〜C-3 スコープ）
- chain 定義（B-3 スコープ）
- workflow の再設計（B-4, B-5 スコープ）
- scripts トップレベルセクション（loom#31 待ち）

## Decisions

### D1: deps.yaml バージョンとスキーマ

v3.0 を宣言する。ref-deps-format の形式に準拠し、以下の構成:

```yaml
version: "3.0"
plugin: dev

entry_points:
  - skills/co-autopilot/SKILL.md
  - skills/co-issue/SKILL.md
  - skills/co-project/SKILL.md
  - skills/co-architect/SKILL.md

skills:
  # controller x4
  co-autopilot: { type: controller, ... }
  co-issue: { type: controller, ... }
  co-project: { type: controller, ... }
  co-architect: { type: controller, ... }
  # workflow（placeholder）
  # atomic skills（placeholder）
  # reference（placeholder）

commands:
  # atomic / composite（placeholder）

agents:
  # specialist（placeholder）
```

controller 4つは完全定義。他コンポーネントは placeholder コメントのみ。

### D2: ディレクトリ構造

```
main/
├── .claude-plugin/
│   └── plugin.json
├── .gitignore
├── CLAUDE.md
├── deps.yaml
├── hooks.json
├── skills/
│   ├── co-autopilot/
│   │   └── SKILL.md    # placeholder
│   ├── co-issue/
│   │   └── SKILL.md    # placeholder
│   ├── co-project/
│   │   └── SKILL.md    # placeholder
│   └── co-architect/
│       └── SKILL.md    # placeholder
├── commands/            # 空（C-2 で追加）
├── agents/              # 空（C-3 で追加）
├── refs/                # 空（C-1 で追加）
├── scripts/
│   └── hooks/
│       ├── post-tool-use-validate.sh
│       └── post-tool-use-bash-error.sh
├── architecture/        # 既存
├── openspec/            # 既存
└── tests/               # 既存
```

### D3: placeholder SKILL.md の形式

各 controller の SKILL.md は frontmatter + 最小限の説明のみ:

```markdown
---
name: twl:co-autopilot
description: ...
type: controller
spawnable_by: [user]
---

# co-autopilot

（C-1 以降で実装）
```

loom validate が pass するための最低限の構造を提供する。

### D4: hooks.json 構成

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "bash scripts/hooks/post-tool-use-validate.sh"
      },
      {
        "matcher": "Bash",
        "command": "bash scripts/hooks/post-tool-use-bash-error.sh $EXIT_CODE"
      }
    ]
  }
}
```

- PostToolUse (Edit/Write): `loom validate` 実行。violation があれば報告
- PostToolUse (Bash): exit_code != 0 の場合 `.self-improve/errors.jsonl` に記録（B-7 基盤）

### D5: CLAUDE.md 追記内容

既存の CLAUDE.md に以下を追記:
- bare repo 構造検証ルール（3条件チェック）
- セッション起動ルール（main/ 必須、worktrees/ 禁止）
- deps.yaml 編集フローの具体化

### D6: .gitignore

```
.self-improve/
*.jsonl
.code-review-graph/
```

## Risks / Trade-offs

- **loom#31 未完了**: scripts トップレベルセクションが使えないため、hook スクリプトは scripts/hooks/ に配置するが deps.yaml には含めない。loom#31 完了後に追加予定
- **loom#28 未完了**: 新規構築のため rename コマンド不要。ただし将来の co-* rename 保守には loom#28 が必要
- **placeholder SKILL.md**: loom validate は pass するが、実際のワークフローは動作しない。C-1〜C-3 で実装が必要
- **controller の calls 未定義**: skeleton では calls を空にする。B-3〜B-5 で chain-driven 定義と共に追加
