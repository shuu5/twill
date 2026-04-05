## Context

Autopilot Worker はヘッドレス（tmux window 内で cld を起動）で動作する。現在 hooks/hooks.json には PostToolUse（Edit/Write 後の validate）と PostToolUseFailure（Bash エラー記録）の 2 エントリのみ存在する。

Claude Code は 24 種の hook イベントを提供しており、そのうち以下が autopilot のヘッドレス安定性に直接寄与する:

- **PreToolUse**: tool 実行前にインターセプト可能。`permissionDecision: "allow"` + `updatedInput` で tool 入力を改変できる
- **PostCompact**: compaction 完了後に発火。観測専用（ブロック不可）
- **PermissionRequest**: permission ダイアログ発生時に発火。`allow/deny` で自動応答可能

Issue #81 では `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` 環境変数が記載されているが、公式ドキュメントに該当する環境変数は存在しない。compaction 閾値の直接制御は不可のため、PostCompact hook による事後対応に限定する。

## Goals / Non-Goals

**Goals:**

- PreToolUse hook で AskUserQuestion を自動応答し、ヘッドレス Worker の UI ブロックを解消する
- PostCompact hook で compaction 発生時に autopilot 進捗のチェックポイントを保存する
- PermissionRequest hook で Worker の permission ダイアログを自動承認する
- 既存の PostToolUse / PostToolUseFailure hook と共存する

**Non-Goals:**

- compaction 閾値の変更（公式 API なし）
- SessionEnd hook の利用（Worker 終了後のクリーンアップは crash-detect.sh が担当）
- CwdChanged / FileChanged / WorktreeCreate / WorktreeRemove hook の利用（autopilot に直接的なメリットなし）
- Claude Code 本体のバージョンアップ手順（スコープ外）

## Decisions

### D1: AskUserQuestion 自動応答の実装方式

PreToolUse hook スクリプト（pre-tool-use-ask-user-question.sh）を作成し、hooks.json の PreToolUse セクションに AskUserQuestion matcher で登録する。

スクリプトは stdin から JSON を受け取り、`tool_input.questions` を解析。各 question の最初の option を自動選択し、`updatedInput.answers` として返す。option がない open-ended question の場合は `"(autopilot: skipped)"` を回答として設定する。

**根拠**: Worker がヘッドレスで動作する以上、AskUserQuestion に人間が回答することは不可能。最初の選択肢を選ぶのは安全なデフォルトであり、Worker は結果を検証して必要に応じて別のアプローチを取れる。

### D2: PostCompact チェックポイントの実装方式

PostCompact hook スクリプト（post-compact-checkpoint.sh）を作成し、hooks.json に登録する。

スクリプトは以下を実行:
1. 環境変数 `AUTOPILOT_DIR` が設定されているか確認（autopilot 配下でのみ動作）
2. state-read.sh で現在の issue 番号を取得
3. state-write.sh で `last_compact_at` タイムスタンプを記録

**根拠**: PostCompact は観測専用だが、タイムスタンプ記録により Pilot がコンテキスト消失リスクを判定できる。

### D3: PermissionRequest 自動承認の実装方式

PermissionRequest hook スクリプト（permission-request-auto-approve.sh）を作成する。

スクリプトは autopilot 配下（`AUTOPILOT_DIR` 設定時）のみ `allow` を返し、通常セッションでは何もしない（exit 0、JSON 出力なし）。

**根拠**: Worker はヘッドレスのため permission ダイアログに応答できない。autopilot 配下に限定することで通常使用時のセキュリティを維持する。

### D4: hooks.json の構造

既存の hooks.json にエントリを追加する形で拡張する。新規 hook イベントキーは既存と同列に配置:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write", ... },
      { "matcher": "AskUserQuestion", ... }
    ],
    "PostToolUse": [ ... ],
    "PostToolUseFailure": [ ... ],
    "PostCompact": [ ... ],
    "PermissionRequest": [ ... ]
  }
}
```

### D5: CLAUDE_AUTOCOMPACT_PCT_OVERRIDE について

Issue #81 P1 で言及されているが、公式ドキュメントに該当する環境変数は存在しない。実装時に `claude --help` や最新リリースノートで再確認し、存在すれば追加、存在しなければ Issue にコメントしてスキップする。

## Risks / Trade-offs

| リスク | 影響 | 緩和策 |
|--------|------|--------|
| AskUserQuestion の自動選択が不適切な回答を返す | Worker が誤った方向に進む可能性 | 最初の option を選択するのは最も安全なデフォルト。Worker は結果を検証可能 |
| PermissionRequest の自動承認で危険な操作が通る | セキュリティリスク | AUTOPILOT_DIR 設定時のみ有効化。通常セッションには影響なし |
| PostCompact の state-write が失敗する | チェックポイント消失 | エラーは無視して Worker 実行を継続（観測目的のため） |
| CLAUDE_AUTOCOMPACT_PCT_OVERRIDE が存在しない | P1 の一部が未達 | PostCompact による事後対応で代替。Issue にコメント |
