## Vision

Claude Code プラグインのための構造定義・検証・可視化フレームワーク CLI を提供する。
「機械的にできることは機械に任せる」原則に基づき、プラグイン構造の正しさを型システムと検証コマンドで保証する。

## Constraints

- **Python 単一ファイル**: twl-engine.py 1ファイルで全機能を完結。Python 3.8+ を対象（f-string, dataclass, typing を使用）
- **外部依存の最小化**: 標準ライブラリ + PyYAML のみ必須。tiktoken（トークン計測）、rich（表示）はオプショナル依存
- **Claude Code プラグインシステム準拠**: Claude Code の skills/commands/agents セクション仕様に従う
- **deps.yaml が SSOT**: 全てのメタデータはここから導出。バージョンは "1.0"（レガシー）, "2.0"（標準）, "3.0"（chains 対応）
- **types.yaml が型ルール SSOT**: can_spawn/spawnable_by の型制約を外部ファイルで管理。twl-engine.py 起動時にロード

## Non-Goals

- **プラグインの実行時動作の制御**: Claude Code 本体の責務であり、twl は構造検証のみを担う
- **AI/LLM の判断を代行する機能**: 判断はプラグインの controller/workflow が担う。twl は機械的に検証可能な項目のみを扱う
- **プラグインのコード生成**: scaffold は将来検討だが現時点では YAGNI。構造定義と検証に集中する
- **deps.yaml の自動生成**: deps.yaml はユーザーが手動で記述する設計。twl は検証と可視化のみ
