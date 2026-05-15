## Vision

TWiLL (Type-Woven, invariant-Led Layering) は Claude Code プラグインの開発・検証・運用を統合するモノリポ。
「機械的にできることは機械に任せる」原則を CLI・プラグイン・仕様管理の全層で一貫させる。

## Constraints

- **モノリポ単一ブランチ**: bare repo + worktree 運用。main が唯一の長期ブランチ
- **コンポーネント自律性**: 各コンポーネント（cli/twl, plugins/twl, plugins/session）は独立した関心事を持ち、自身の CLAUDE.md で開発ルールを定義する
- **依存方向の一方向性**: plugins → cli の方向のみ許可。cli は plugins を知らない
- **SSOT 原則**: deps.yaml（プラグイン構造）、types.yaml（型ルール）が各領域の唯一の情報源

## Non-Goals

- **全コンポーネント統合テスト**: 各コンポーネントは独立してテスト可能。統合テストはプラグインの機能テストで代替
- **共有ライブラリ/共通コード**: コンポーネント間のコード共有は行わない。各自が必要なものを自己完結で持つ
- **パッケージマネージャ統合**: npm/pip 等のワークスペース機能は使用しない。symlink で運用
