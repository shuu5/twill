# ADR-0011: MCP Shadow Hook と Bash Hook の責務分離

**Status**: Accepted
**Date**: 2026-05-03
**Issue**: #1334

## Context

`PreToolUse:Bash` hook には 2 種類の実装が共存している:

1. **Bash hook** (`pre-bash-commit-validate.sh` 等): 実行前にブロック/中断を行う
2. **MCP shadow hook** (`twl_validate_commit` 等): MCP tool として副作用なしに記録・検査する

Issue #1288 で MCP shadow hook が追加された際、`twl_validate_commit` の入力スキーマと
`settings.json` の hook 設定が整合しておらず、`message` パラメータに full git command 文字列が
渡されるという不整合が発生していた（Issue #1334 で検出）。

## Decision

### 責務分離の原則

| 層 | 実装 | 役割 |
|---|---|---|
| **ブロック層** | Bash hook (`pre-bash-commit-validate.sh`) | コミットを実際に止める (exit code != 0 で中断) |
| **記録層** | MCP shadow hook (`twl_validate_commit`) | コマンドを記録・検査する (outputType=log、ブロックしない) |

### `twl_validate_commit` の修正方針 (Issue #1334)

- パラメータを `message: str` → `command: str` に変更し、full git command 文字列を受け取る
- 内部で `extract_commit_message_from_command()` によりメッセージ本文を抽出する
- `settings.json` の hook input を `"command": "${tool_input.command}"` に統一する
- MCP shadow は記録専用 (`outputType: "log"`) — ブロックは Bash hook が担当

### なぜ `command: str` か

PreToolUse:Bash hook の `tool_input.command` は Bash コマンド全体
（例: `git commit -m "feat: add X"`）を渡す。
handler 内部でコマンド文字列を解析してメッセージを抽出することで、
hook 設定を単純化し（`tool_input.command` をそのまま渡す）、
将来的な `-m`/`--message` 以外のオプション対応も handler 内に集約できる。

## Alternatives Considered

### Option 1: `message: str` パラメータを維持し hook 側でメッセージ抽出

hook 設定で `"message": "$(echo '${tool_input.command}' | sed 's/.*-m //')"` 等のシェル展開でメッセージを抽出する案。

**却下理由**: Claude Code の settings.json は変数展開に対応しているが、シェルコマンドの埋め込みは非サポート。また hook 側に解析ロジックを置くと責務が分散し、将来の `-m`/`--message`/`-F` 拡張が困難になる。

### Option 2: MCP shadow hook の廃止

`twl_validate_commit` MCP hook 自体を削除し、bash hook のみでバリデーションを行う案。

**却下理由**: MCP shadow hook は記録・監視（将来的なメトリクス収集）の用途を持つ。また PR #1332 / Issue #1288 のレビューで shadow hook パターンが設計として確立されており、廃止は過剰な変更となる。

## Consequences

- `twl_validate_commit` の `command` パラメータは full git command 文字列を受け取る
- `-F`（ファイルから読む）形式は `extract_commit_message_from_command` が `""` を返す (no-op)
- MCP shadow hook は記録専用であり、検証ブロックは bash hook 側で行う
- 既存 `pre-bash-commit-validate.sh` は変更不要（責務変更なし）
