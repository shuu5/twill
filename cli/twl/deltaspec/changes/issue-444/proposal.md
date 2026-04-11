## Why

autopilot の full chain（setup → test-ready → pr-verify → pr-merge）は GitHub Issue/PR を前提とした chain 遷移を持つが、現在の `--local-only` モードではローカルファイル配置のみで chain 遷移を通せない。Bug #436/#438/#439 の再現・回帰防止には実際の GitHub Issue + PR を使った full chain 実行基盤が必要。

## What Changes

- `--real-issues` モードの設計ドキュメントを ADR-016 として追加
- テスト用リポジトリ分離戦略の比較検討（専用リポ / 実リポ test ラベル / mock GitHub API）
- co-self-improve の scenario-run モードへの `--real-issues` 分岐統合フロー設計
- テスト後クリーンアップ設計（Issue close, PR close, branch 削除）
- リポジトリ作成・管理の責務帰属の決定

## Capabilities

### New Capabilities

- `--real-issues` モード: GitHub Issue 起票 → autopilot 実行 → observe の full chain 実行フロー
- テスト対象リポジトリの分離戦略: 実リポジトリの git 履歴を汚染しない隔離設計
- クリーンアップパイプライン: テスト完了後の GitHub リソース（Issue/PR/branch）後処理

### Modified Capabilities

- co-self-improve scenario-run モード: `--real-issues` フラグ対応の分岐ロジック追加（設計のみ）
- test-project-init または新規コマンド: テスト用リポジトリ作成・管理の責務拡張（設計のみ）

## Impact

- 影響ファイル: `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md`（新規）
- 依存 API: GitHub REST API（Issue/PR 作成・クローズ・削除）
- 設計のみ（実装 Issue は別途）
