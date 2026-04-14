## Context

Claude Code v2.1.85+ の PreToolUse hook は、ツール実行前にシェルスクリプトを介して stdin JSON を受け取り、exit 2 でブロックできる。現在 deps.yaml の検証は PostToolUse のみで行われており、壊れた YAML が disk に書き込まれた後に `twl --check` がクラッシュする問題がある。`if` フィールドで対象ファイルを絞り込めるため、パフォーマンス影響を最小化できる。

## Goals / Non-Goals

**Goals:**
- Write(deps.yaml) および Edit(deps.yaml) 実行前に YAML syntax を検証し、不正な場合は exit 2 でブロックする
- Edit の場合は `old_string`/`new_string` を使った simulated apply で検証する
- 正常な YAML および deps.yaml 以外のファイルには影響を与えない
- deps.yaml に新規スクリプトをコンポーネントとして登録する

**Non-Goals:**
- PostToolUse hook の修正
- YAML の型ルールチェック（Post 層の責務）
- git commit gate
- `twl --validate` による意味的検証

## Decisions

**simulated apply の実装**: bash の `${current//"$old_str"/"$new_str"}` で文字列置換を行う。正規表現は使わないため glob 展開を防ぐために `set -f` を適用する。Edit ツール自体が unique マッチを前提としているため、複数マッチの問題は実用上発生しない。

**YAML 検証コマンド**: `python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"` を使用。外部ライブラリへの依存なしに ~0.05s で実行可能。`python3` と `pyyaml` はプロジェクト環境で利用可能。

**hook の `if` 条件**: `Edit(deps.yaml)|Write(deps.yaml)` で絞り込む。`if` が false のとき hook プロセスは spawn されないため、他のファイル編集にパフォーマンス影響なし。

**timeout**: 3000ms。YAML parse は通常 50ms 以内であり、十分なマージン。

## Risks / Trade-offs

- `old_string` に bash 特殊文字が含まれる極端なケースでは simulated apply が不正確になる可能性があるが、`set -f` と引用符で実用上のリスクは低い
- `python3` または `pyyaml` が存在しない環境では hook がエラーになる可能性があるが、プロジェクトの開発環境では必須依存として保証される
