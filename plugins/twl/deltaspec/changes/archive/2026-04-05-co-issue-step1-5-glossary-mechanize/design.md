## Context

- `~/.claude/settings.json` は `~/ubuntu-note-system/claude/settings.json` へのsymlinkで、ubuntu-note-systemリポで管理
- `hooks.PreToolUse` は `[{matcher, hooks: [{type, command, timeout}]}]` 形式
- フック命令の終了コード 2 + stderr メッセージで操作をブロックできる
- `TOOL_INPUT_file_path` 環境変数でツール引数のファイルパスを参照できる
- SKILL.md の対象行は Step 1.5 ステップ3（現在: 「explore-summary.md の用語と MUST 用語を照合し、完全一致しない用語を列挙する」）

## Goals / Non-Goals

**Goals:**

- `architecture/domain/glossary.md` への Edit/Write をフックでブロック（機械的ガード）
- co-issue SKILL.md Step 1.5 ステップ3の照合方向を「explore-summary → glossary」と一意に明記

**Non-Goals:**

- glossary.md の自動更新機能（co-architect の責務）
- deps.yaml の変更（既存コンポーネントの修正のみ）
- loom check 変更なし

## Decisions

### PreToolUse フック形式

`hooks.PreToolUse` 配列に以下を追加:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "bash -c 'case \"$TOOL_INPUT_file_path\" in *architecture/domain/glossary.md) echo \"glossary.md の変更は /twl:co-architect 経由で行ってください\" >&2; exit 2;; esac'",
      "timeout": 3000
    }
  ]
}
```

Exit code 2 + stderr でブロック。既存の Edit/Write フックがないため新規エントリとして追加。

### SKILL.md 文言修正

ステップ3の現在の記述:
> `explore-summary.md の用語と MUST 用語を照合し、完全一致しない用語を列挙する（部分一致・略語は除外）`

修正後:
> `explore-summary.md から抽出した用語のうち、MUST 用語テーブルに存在しない（未登録の）用語を列挙する（部分一致・略語は除外）`

### デプロイ順序

1. ubuntu-note-system/claude/settings.json 変更 → ubuntu-note-system リポでコミット → `./scripts/deploy.sh --all`
2. loom-plugin-dev/skills/co-issue/SKILL.md 変更 → loom-plugin-dev リポでコミット

## Risks / Trade-offs

- `TOOL_INPUT_file_path` は絶対パスか相対パスか環境依存のため、`*` glob で末尾マッチを使用する（`case` の `*architecture/domain/glossary.md`）
- フック追加は全セッションに影響するが、既存の Edit/Write 操作への影響は glossary.md のみ
