## Why

co-issue Step 1.5 の「glossary.md への自動書き込みは禁止」が自然言語制約のみで機械的ガードがなく、LLM が誤って書き込む可能性がある。また、Step 1.5 ステップ3の照合方向が曖昧で、「explore-summary → glossary」方向であることが単体では判断できない。

## What Changes

- `~/ubuntu-note-system/claude/settings.json`（`~/.claude/settings.json` symlink 先）に PreToolUse フックを追加し、`architecture/domain/glossary.md` への Edit/Write をブロック
- `skills/co-issue/SKILL.md` の Step 1.5 ステップ3を「explore-summary から抽出した用語のうち MUST 用語テーブルに未登録のものを列挙する」に修正

## Capabilities

### New Capabilities

- **glossary.md 機械的ガード**: PreToolUse フックが `architecture/domain/glossary.md` への Edit/Write を検出してブロック。メッセージ: 「glossary.md の変更は /twl:co-architect 経由で行ってください」

### Modified Capabilities

- **Step 1.5 ステップ3 文言**: 「照合して未登録用語を列挙する」→「explore-summary から抽出した用語のうち MUST 用語テーブルに存在しない（未登録の）用語を列挙する」に一意化

## Impact

- `~/ubuntu-note-system/claude/settings.json` — PreToolUse フック追加（ubuntu-note-system リポでコミット・`./scripts/deploy.sh --all` でデプロイ）
- `skills/co-issue/SKILL.md` — Step 1.5 ステップ3 文言修正（loom-plugin-dev リポ）
- `deps.yaml` 変更なし（既存コンポーネントの修正のみ）
