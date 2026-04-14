## Context

TWiLL プロジェクトでは deps.yaml の型ルール整合性を `twl --validate` で検証するが、現状このコマンドはコミット前に自動実行されない。PreToolUse hook（`.claude/settings.json`）を使い `git commit` Bash ツール呼び出し時にスクリプトを介して `twl --validate` を実行する。

settings.json の `hooks.PreToolUse[].hooks[].if` フィールドが Claude Code でサポートされているか未確認のため、スクリプト内で `$TOOL_INPUT_command` を参照する方式をフォールバック標準とする。

## Goals / Non-Goals

**Goals:**

- `git commit` 実行前に `twl --validate` を自動実行し、violations > 0 の場合に exit 2 でコミットをブロックする
- `TWL_SKIP_COMMIT_GATE=1` 環境変数によるバイパスを提供する（Issue E 完了前の安全装置）
- deps.yaml が存在しない場合（worktree 外など）は hook をスキップする
- `git commit` 以外の Bash コマンドには影響しない

**Non-Goals:**

- deps.yaml の変更時の Pre/Post hook（Issue A, B）
- 既知違反の解消（Issue E）
- architecture ファイルのガード（Issue D）
- 他プロジェクトへの適用

## Decisions

**スクリプト内 git commit 検出（`$TOOL_INPUT_command` フォールバック）**
settings.json の `if` フィールドが PreToolUse でサポートされているか未確認のため、スクリプト先頭で `$TOOL_INPUT_command` を参照し `git commit` パターン以外は即 exit 0 する。`if` フィールドがサポートされている場合は settings 側にも追加して defense-in-depth を実現する。

**hook CWD とスクリプト配置**
hook の CWD はプロジェクトルート。`twl --validate` は `plugins/twl/` でのみ動作するため、スクリプト内で `cd plugins/twl` を実行。deps.yaml が見つからない場合は exit 0 でスキップ。

**exit code 2 でブロック**
Claude Code の PreToolUse hook は exit 2 をブロックシグナルとして扱う。exit 0 は通過。exit 1 はエラーとして扱われる可能性があるため、ブロック専用の exit 2 を使用する。

**deps.yaml へのエントリ追加**
`plugins/twl/deps.yaml` の `scripts` セクションに `hooks/pre-bash-commit-validate.sh` を追加し、loom CLI の管理下に置く。

## Risks / Trade-offs

- `twl --validate` の実行時間は ~0.4s。git commit 頻度が高い環境では微小な遅延が積み重なる可能性があるが、通常の開発では許容範囲
- Issue E（既知 13 違反）解消前に hook が有効になると全コミットがブロックされるため、`TWL_SKIP_COMMIT_GATE=1` バイパスを必須とする
- settings.json の `if` フィールドサポート状況が不明なため、スクリプト内フォールバックを標準実装とする（両方実装でリスク低減）
