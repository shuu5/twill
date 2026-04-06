## 1. COMMAND.md 作成（6 コンポーネント）

- [x] 1.1 `commands/ac-deploy-trigger.md` を作成（旧プラグインから移植、ディレクトリ構造に変換）
- [x] 1.2 `commands/test-phase.md` を作成（chain 外スタンドアロン、specialist は Task tool 呼び出し）
- [x] 1.3 `commands/auto-merge.md` を作成（autopilot-first 簡素化、--auto-merge フラグ除去）
- [x] 1.4 `commands/pr-cycle-analysis.md` を作成（4 カテゴリパターン分析、doobidoo 連携）
- [x] 1.5 `commands/schema-update.md` を作成（webapp-hono 専用、5 ステップワークフロー）
- [x] 1.6 `commands/spec-diagnose.md` を作成（テスト失敗診断、修正禁止）

## 2. deps.yaml 更新

- [x] 2.1 6 コンポーネントの deps.yaml エントリ追加（C-2c セクション）
- [x] 2.2 merge-gate の calls に `atomic: auto-merge` を追加
- [x] 2.3 workflow-pr-cycle の calls に ac-deploy-trigger, ac-verify, pr-cycle-analysis を追加

## 3. 検証

- [x] 3.1 `loom check` で構造検証 pass
- [x] 3.2 全 18 コンポーネントが deps.yaml に存在することを確認
- [x] 3.3 --auto-merge 関連コード（フラグ分岐、マーカーファイル、DEV_AUTOPILOT_SESSION）が存在しないことを確認
