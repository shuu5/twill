## Why

C-2a/C-2b で独立コンポーネントと setup chain が移植完了したが、PR サイクル関連の 6 コンポーネント（ac-deploy-trigger, test-phase, auto-merge, pr-cycle-analysis, schema-update, spec-diagnose）が未移植。全 18 コンポーネントを deps.yaml v3.0 に揃え、chain-driven + autopilot-first 設計に統一する。

## What Changes

- 未移植 6 コンポーネントの COMMAND.md を新規作成し deps.yaml に登録
- 旧プラグインの `--auto-merge` フラグ分岐・環境変数チェック・マーカーファイル管理を除去
- auto-merge を autopilot-first 前提で簡素化（merge-gate の呼び出し先として機能）
- 既存 12 コンポーネントの deps.yaml 定義に不足があれば補完

## Capabilities

### New Capabilities

- ac-deploy-trigger: AC テキストから外部アクセスキーワードを検出し deploy E2E フラグを設定
- test-phase: サービスヘルスチェック + E2E 品質ゲート + テスト実行の統合フェーズ
- auto-merge: squash マージ → archive → cleanup の実行（autopilot-first、merge-gate から呼び出し）
- pr-cycle-analysis: PR-cycle 結果からパターン分析し self-improve Issue 自動起票
- schema-update: Zod スキーマ更新 + OpenAPI 再生成 + 検証ワークフロー（webapp-hono 専用）
- spec-diagnose: テスト失敗の原因を診断し仕様誤りか実装誤りかを判定

### Modified Capabilities

- deps.yaml: 6 コンポーネント定義の追加、calls 関係の明示
- workflow-pr-cycle: chain step と呼び出し関係を B-5 chain 定義と整合

## Impact

- deps.yaml v3.0 に全 18 コンポーネント登録で loom validate pass が必要
- merge-gate（B-5 スコープ）からの auto-merge 呼び出しインターフェースを定義
- 旧プラグインの --auto-merge 関連コードは完全除去
