## Vision

Claude Code プラグインのための構造定義・検証・可視化フレームワーク CLI を提供する。
「機械的にできることは機械に任せる」原則に基づき、プラグイン構造の正しさを型システムと検証コマンドで保証する。

## Constraints

- Python 単一ファイル（loom-engine.py）で完結。外部依存は最小限
- Claude Code のプラグインシステム仕様に準拠
- deps.yaml が SSOT。全てのメタデータはここから導出

## Non-Goals

- プラグインの実行時動作の制御（それは Claude Code 本体の責務）
- AI/LLM の判断を代行する機能（判断はプラグインの controller/workflow が担う）
- プラグインのコード生成（scaffold は将来検討だが現時点では YAGNI）
