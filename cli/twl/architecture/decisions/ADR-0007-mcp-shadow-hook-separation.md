# ADR-0007: MCP Shadow Hook と Bash Hook の責務分離

**ステータス**: Accepted  
**日付**: 2026-05-03  
**関連 Issue**: #1335 (#1288 follow-up)

## 背景

`.claude/settings.json` の `PreToolUse:Bash` hook に `twl_validate_commit` MCP ツールを登録している。
このツールは `files` パラメータに渡された deps.yaml ファイルを検証することが意図されているが、
Claude Code の hook 仕様上の制約により、`tool_input` から staged files リストを取得する手段がない。
そのため `files` は常に空リスト `[]` で呼び出され、ループがスキップされて常に `ok=true` を返す。

## 決定

MCP hook（`twl_validate_commit`）と bash hook（`pre-bash-commit-validate.sh`）の責務を明確に分離する:

| Hook 種別 | 実装 | 責務 |
|-----------|------|------|
| bash hook | `pre-bash-commit-validate.sh` | **block 専用**: deps.yaml validation を行い、違反時に exit non-zero でコミットをブロック |
| MCP hook | `twl_validate_commit` | **記録専用 (shadow mode)**: 将来の hook 仕様拡張に備えた登録・ログ記録のみ。現状は no-op |

## 理由

- Claude Code の `PreToolUse` hook では `tool_input` からファイルリストを取得できない（仕様制約）
- `pre-bash-commit-validate.sh` が同等の検証を提供しており、実際の防衛線として機能している
- MCP hook を削除するより「shadow mode として意図を明示した上で存在させる」ことで、
  将来の hook 仕様拡張時に容易に有効化できる
- `outputType: "log"` の設定により、MCP hook の失敗がユーザー体験に影響しない

## 将来の変更

Claude Code の hook 仕様が拡張されて `tool_input` から staged files が取得可能になった場合:
1. `twl_validate_commit_handler` の `files` パラメータを実際に活用するよう更新
2. `settings.json` の `files: []` を動的なファイルリストに変更
3. 本 ADR のステータスを Superseded に更新し、新 ADR を作成すること
