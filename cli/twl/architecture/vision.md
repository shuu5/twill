## Vision

TWiLL フレームワークの統合 CLI ツール。Claude Code プラグインの構造定義・検証・可視化に加え、変更仕様（delta spec）のライフサイクル管理を提供する。
「機械的にできることは機械に任せる」原則に基づき、プラグイン構造の正しさを型システムと検証コマンドで保証し、仕様駆動の開発ワークフローを支援する。

## Constraints

- **Python パッケージ構造**: `src/twl/` 配下に Bounded Context 単位でモジュール分割（ADR-0003）。Python 3.10+ を対象
- **外部依存の最小化**: 標準ライブラリ + PyYAML のみ必須。tiktoken（トークン計測）、rich（表示）はオプショナル依存
- **Claude Code プラグインシステム準拠**: Claude Code の skills/commands/agents セクション仕様に従う
- **deps.yaml が SSOT**: プラグイン構造の全メタデータはここから導出。バージョンは "1.0"（レガシー）, "2.0"（標準）, "3.0"（chains 対応）
- **types.yaml が型ルール SSOT**: can_spawn/spawnable_by の型制約を外部ファイルで管理

## Non-Goals

- **プラグインの実行時動作の制御**: Claude Code 本体の責務であり、twl は構造検証のみを担う
- **AI/LLM の判断を代行する機能**: 判断はプラグインの controller/workflow が担う。twl は機械的に検証可能な項目のみを扱う
- **プラグインのコード生成**: scaffold は将来検討だが現時点では YAGNI。構造定義と検証に集中する
- **deps.yaml の自動生成**: deps.yaml はユーザーが手動で記述する設計。twl は検証と可視化のみ
