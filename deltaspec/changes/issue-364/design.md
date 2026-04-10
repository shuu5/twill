## Context

Claude Code セッション内で長期作業が続くと /compact が自動実行され、作業中の知識・タスク状態・Supervisor Session 情報が失われる。現在 su-observer は Memory MCP への外部化機能を持つが、コマンドとして明示的に呼び出せる統合窓口がない。`su-compact` はユーザーが意図的に知識外部化 + compaction を制御するための単一エントリポイントコマンドとして設計する。

依存コンポーネント:
- Memory MCP（doobidoo）: `refs/memory-mcp-config.md` 参照
- externalize-state: SupervisorSession 状態のファイル書出（別 Issue で実装済み想定）
- /compact: Claude Code 組み込み compaction コマンド

## Goals / Non-Goals

**Goals:**

- `su-compact` コマンドの新規作成（`plugins/twl/commands/su-compact.md`）
- `--wave`, `--task`, `--full` の 3 オプション対応
- Memory MCP（refs/memory-mcp-config.md）を参照した Long-term Memory 保存
- `.supervisor/working-memory.md` への Working Memory 退避
- /compact 実行前の確認フロー
- `plugins/twl/deps.yaml` へのコンポーネント登録

**Non-Goals:**

- externalize-state コマンドの実装（別 Issue 管理）
- /compact の挙動変更
- 自動発火 hook の作成（ユーザーが明示的に呼ぶことが前提）

## Decisions

**D1: コマンドタイプ = atomic（workflow ではなく）**
- 処理ステップが直線的でユーザー対話が少ないため atomic が適切
- workflow 化は over-engineering となる

**D2: オプション判定は引数から**
- `--wave` / `--task` / `--full` を引数で受け取り、なければ状況自動判定
- 自動判定ロジック: タスク状態あり→task, Wave完了サマリあり→wave, それ以外→full

**D3: Memory MCP 参照は refs/memory-mcp-config.md を経由**
- ハードコードではなく config 経由で MCP ツール名を解決
- 将来の MCP 入れ替えに対応

**D4: externalize-state 呼出タイミング**
- Step 2（Long-term Memory 保存）の後、Step 3（Working Memory 退避）と同時に実行
- externalize-state が存在しない場合はスキップ（警告のみ）

## Risks / Trade-offs

- **externalize-state 依存**: 未実装の場合は Working Memory のみ退避してスキップ
- **/compact の副作用**: 実行後はコンテキストが失われるため、su-compact 内で事前に全保存を完結させる必要あり
- **Memory MCP の空打ち**: 外部化する知識が少ない場合も store が走るが、無害
