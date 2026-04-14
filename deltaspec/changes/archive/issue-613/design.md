## Context

su-observer は長時間常駐する Claude Code セッション（observer ウィンドウ）を管理する。セッション状態は `.supervisor/session.json` に保存されるが、現状 Claude Code session ID は記録されていない。ユーザーが observer ウィンドウに戻る際、session ID がわからず `claude --resume` による復帰が困難。

`cld` スクリプトは現状 `set -euo pipefail` + `exec claude ...` 構成で、全引数をそのまま `claude` にパススルーする。引数パースロジックがないため、`--observer` フラグの intercept には引数ループでの事前チェックが必要。

## Goals / Non-Goals

**Goals:**
- Claude Code session ID を `su-observer` 起動時に `.supervisor/session.json` へ保存
- `cld --observer` で保存済み session ID を使って `claude --resume` を自動実行
- session ID の有効性確認（tmux window 存在・Claude Code プロセス生存）
- compaction 後の session ID 更新（AC-0 の検証結果次第で `su-postcompact.sh` に追加）
- `SupervisorSession` エンティティへの `claude_session_id` フィールド追加
- エラーケース（session.json 不在・ID 空・window 不在・プロセス終了）の適切なメッセージ

**Non-Goals:**
- `cld-ch` への `--observer` フラグ追加（tmux window 切り替え用で別レイヤー）
- 複数プロジェクト間の observer 切り替え UI
- session ID の自動ローテーション

## Decisions

### Session ID 取得方法（AC-0 で検証後に確定）

優先順で試行:
1. **環境変数** `CLAUDE_SESSION_ID`（Claude Code が設定している場合）
2. **JSONL ファイル推定**: `~/.claude/projects/<project-hash>/` 配下の最新 `.jsonl` ファイル名から抽出
3. **Hook stdin**: SessionStart hook の stdin JSON（実測で確認）

co-issue の `pre-bash-phase3-gate.sh` では `${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}` と使用されており、常に利用可能とは限らない。**実装前に AC-0 検証を必須とする。**

### `cld --observer` 引数パース設計

`--observer` を `exec` の前で intercept する:
```bash
PASS_ARGS=()
OBSERVER_MODE=false
for arg in "$@"; do
  if [[ "$arg" == "--observer" ]]; then
    OBSERVER_MODE=true
  else
    PASS_ARGS+=("$arg")
  fi
done
```
`--observer` 検出時は `exec claude` に到達せず、代わりに `claude --resume <claude_session_id>` を exec する分岐を設ける。

### session-state.sh 活用

有効性確認では `session-state.sh list --json` で window 一覧を取得し、`session-state.sh state <window>` で状態を判定する。`session-state.sh` は `plugins/session/scripts/` に配置され、symlink 経由で PATH 上に存在する。

### su-postcompact.sh の責務拡張

session ID 更新の追加は責務の拡張となるため、PostCompact hook 内で別スクリプトに分離するか、明確なセクション分離を設ける。AC-0 の検証結果に依存するため、compaction 後に ID が変わる場合のみ実装する。

## Risks / Trade-offs

- **Session ID 取得の不安定性**: `CLAUDE_SESSION_ID` が常に利用可能とは限らない → AC-0 検証で安定する方法を確定する
- **JSONL ファイル推定の精度**: 最新ファイルが必ずしも現在のセッションとは限らない
- **Compaction 時の ID 変更**: `/compact` 後に session ID が変わる場合、`--observer` での resume が失敗する可能性 → AC-0 で検証
- **cld の引数パース導入**: 現状のシンプルな全パススルー設計から変更するため、既存フラグ互換性を確認する（AC-8）
