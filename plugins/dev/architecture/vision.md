## Vision

chain-driven + autopilot-first アーキテクチャに基づく Claude Code 開発ワークフロープラグイン。
旧 dev plugin (claude-plugin-dev) の複雑性ホットスポットを解消し、「機械的にできることは機械に任せる」原則を徹底する。

## Constraints

- Loom フレームワーク準拠（deps.yaml v3.0, types.yaml 型システム）
- Claude Code プラグインシステム仕様に準拠
- Controller は4つのみ（co-autopilot, co-issue, co-project, co-architect）
- Bare repo + worktree 一律（branch モード廃止）
- 状態管理は統一 JSON 2種（issue-{N}.json + session.json）

## Non-Goals

- 技術スタック固有の機能（それはコンパニオンプラグインの責務）
- loom CLI 本体の機能開発（shuu5/loom リポジトリの責務）
- AI/LLM の判断を機械化すること（Issue 分解、コードレビュー品質、エラー診断は LLM に任せる）
