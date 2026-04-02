## Why

79/1174 テスト中 70 件が失敗（6.0%）。大半は仕様変更（#47 フラグ廃止、#82 コンポーネント削除、#98 deps.yaml 構造変更）に追従していない旧仕様テストが原因で、リグレッション検知を阻害している。

## What Changes

- `--auto`/`--auto-merge` フラグを期待するテストの修正（#47 で廃止済み）
- `DEV_AUTOPILOT_SESSION` 環境変数を期待するテストの修正
- `check-db-migration` の deps.yaml 登録を期待するテストの修正（#82 で削除済み）
- 旧 chain/step_in 構造を前提とするテストの現行仕様への更新
- health-report.bats のスタブ参照修正
- co-issue SKILL.md 構造テストの期待値修正
- 旧コンポーネント数・ファイル数を期待するカウントテストの更新
- merge-gate、pr-cycle、autopilot 関連テストの現行仕様への整合

## Capabilities

### New Capabilities

なし（テスト修正のみ）

### Modified Capabilities

- テストスイートが現行仕様と整合し、PASS 率 100% に回復
- リグレッション検知が正常に機能する状態の回復

## Impact

- 影響範囲: `tests/` ディレクトリ配下のテストファイルのみ
- プロダクションコード変更: なし
- deps.yaml 変更: なし
- 依存: #98（validate violations 修正）完了後に適用
