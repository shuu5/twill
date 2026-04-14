## Why

`main/.code-review-graph` が自己参照 broken symlink に繰り返し壊れる（#532, #605 修正後も W32 で3回目の再発）。現在の realpath ガードは「作成時」の防御だが、LLM ステップ（crg-auto-build）が明示的な禁止なしで symlink を作成できる抜け道が残っており、根本的な封鎖ができていない。

## What Changes

- `plugins/twl/commands/crg-auto-build.md` に symlink 操作の明示的禁止ルールを追加
- `plugins/twl/scripts/autopilot-orchestrator.sh` の CRG symlink セクションにヘルスチェックを追加（壊れた symlink の早期検出・自動修復ログ強化）
- su-observer の Wave 開始/終了フックに `file .code-review-graph` チェックを追加

## Capabilities

### New Capabilities

- **LLM symlink 作成禁止ガード**: `crg-auto-build.md` の MUST NOT セクションに `ln` コマンド実行禁止を追加。LLM が symlink を作成しようとしても、明文ルールで阻止される
- **observer ヘルスチェック**: su-observer が Wave 開始時に `main/.code-review-graph` のリンク状態を自動チェックし、自己参照を検出した場合に即座にアラートを出す

### Modified Capabilities

- **orchestrator CRG セクション**: 既存の realpath ガードに加え、自己参照 symlink が残存している場合の自動修復処理を補強。ガード通過後に `file .code-review-graph` 相当のチェックを実行

## Impact

- `plugins/twl/commands/crg-auto-build.md`: MUST NOT セクション追加（コメント追加のみ、動作変更なし）
- `plugins/twl/scripts/autopilot-orchestrator.sh`: L325-348 の CRG セクション修正（ロジック補強）
- `plugins/twl/skills/su-observer/SKILL.md` または observer スクリプト: Wave 開始フックに CRG ヘルスチェック追加
- テスト: `plugins/twl/tests/unit/crg-symlink-reporoot/crg-symlink-reporoot.bats` に LLM 禁止ガードシナリオ追加
