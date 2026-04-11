## Why

`step_init()` が `deltaspec/` の存在を前提とした判定を行っていたため、Worker worktree には `deltaspec/` が存在せず全 Worker が `recommended_action=direct` を受け取っていた。ADR-015 で `step_init()` が `auto_init=true` を返すよう再設計され（#338）、`change-propose` ステップがその初期化を担う必要がある。

## What Changes

- `plugins/twl/commands/change-propose.md` に `auto_init=true` 判定ロジックを追加
- `auto_init=true` 時: `mkdir -p deltaspec/changes/<change-id>/`、Issue body から `proposal.md` 生成、`.deltaspec.yaml` 作成（status: pending）
- `auto_init=false` 時: 既存の動作を維持
- change-id は Issue 番号ベース（例: `issue-339`）

## Capabilities

### New Capabilities

- `auto_init=true` を受け取った場合に deltaspec/ ディレクトリ構造を自動作成する
- Issue body から proposal.md を自動生成する
- `.deltaspec.yaml` の最小構成（name, status: pending, created_at）を生成する

### Modified Capabilities

- `change-propose` ステップの Step 1（入力解析）を拡張: `auto_init=true` かつ Issue 番号が存在する場合は対話なしで change-id を自動導出する

## Impact

- `plugins/twl/commands/change-propose.md` のみを変更（スコープ限定）
- step_init() の判定ロジック（#338）や deltaspec specs/・テストマッピング生成（後続 test-scaffold）は対象外
- `twl spec new` コマンドを利用するため CLI の挙動に依存する
