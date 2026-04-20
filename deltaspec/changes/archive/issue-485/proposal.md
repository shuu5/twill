## Why

`twl spec new` の auto-init fallback が `find_deltaspec_root()` 失敗時に worktree 直下に `deltaspec/` を silent 作成するため、spec change が canonical な nested root ではなく worktree ルートに配置され、PR merge 時に `main/deltaspec/` に orphan として持ち込まれる。Wave 3 で 2 件の orphan（issue-439、issue-446）が発生し、spec の canonical location が破壊された。

## What Changes

- `cli/twl/src/twl/spec/new.py`: auto-init fallback を Phase 1（nested root 検出時は早期 fail）+ Phase 2（`TWL_SPEC_ALLOW_AUTO_INIT=1` opt-in）に置き換える
- `cli/twl/src/twl/spec/paths.py`: `find_deltaspec_root()` のエラーメッセージに「試したパス一覧」と「rebase 推奨」を追加
- `plugins/twl/scripts/chain-runner.sh`: `step_init` で current branch が post-#435 な main からの rebase を含むか検証するガードを追加
- `plugins/twl/commands/change-propose.md`: auto_init 分岐の `DELTASPEC_EXISTS` チェックを改善（既存 nested root を正しく認識する）
- `cli/twl/tests/spec/test_new.py`: nested root 存在時に auto-init fallback が発動しないことを検証する test を追加
- bats scenario: `feat branch が pre-#435 の場合に twl spec new が早期失敗するケース` を追加

## Capabilities

### New Capabilities

- **auto-init 抑制ガード**: git walk-down で nested `deltaspec/config.yaml` を発見できた場合に auto-init を発動しない。エラーメッセージで `cd <nested-root-parent>` または `git rebase origin/main` を案内する
- **TWL_SPEC_ALLOW_AUTO_INIT opt-in**: 旧 branch の継続作業用に `TWL_SPEC_ALLOW_AUTO_INIT=1` 環境変数で従来の auto-init を一時的に許可する（移行期間用）
- **chain-runner rebase 検証**: `step_init` で `plugins/twl/deltaspec/config.yaml` / `cli/twl/deltaspec/config.yaml` の存在チェックにより post-#435 rebase 状態を確認し、欠落時に WARN + 自動 rebase 提案を出す

### Modified Capabilities

- **find_deltaspec_root エラーメッセージ**: 試行した walk-up パスと walk-down パスをエラーに含め、`git rebase origin/main` を推奨する
- **change-propose auto_init**: `DELTASPEC_EXISTS=false` 判定を `nested deltaspec root が存在しない` に精緻化

## Impact

- `cli/twl/src/twl/spec/new.py`（auto-init fallback ロジック置き換え）
- `cli/twl/src/twl/spec/paths.py`（エラーメッセージ強化）
- `plugins/twl/scripts/chain-runner.sh`（step_init にrebase 検証追加）
- `plugins/twl/commands/change-propose.md`（auto_init 条件改善）
- `cli/twl/tests/spec/test_new.py`（新規テスト）
- `test-fixtures/` または `plugins/twl/tests/`（bats シナリオ追加）
