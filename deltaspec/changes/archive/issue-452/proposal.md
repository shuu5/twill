## Why

`issue-spec-review.md` の CONTEXT_ID 生成に `date +%s%N | tail -c8` を使用しており、予測可能なファイル名（`/tmp/.specialist-manifest-<CONTEXT_ID>.txt`）になることで `/tmp` 上のシンボリックリンク攻撃（CWE-377）のリスクがある。また Wave 3 以降で同コマンドが並列起動される場合、同一秒内に CONTEXT_ID が衝突する可能性がある。

## What Changes

- `issue-spec-review.md:60-63` の CONTEXT_ID 生成を `mktemp` ベースに変更し、ファイルパーミッションを 600 に設定する
- クリーンアップロジック（`:131-140`）を新しい命名規則に追従させる
- `.specialist-spawned-*.txt` / `.specialist-manifest-*.txt` を参照する全箇所を新命名規則に更新する
- 並列起動シナリオのテストを追加する

## Capabilities

### New Capabilities

- なし（内部実装の改善のみ）

### Modified Capabilities

- **issue-spec-review manifest 生成**: `date +%s%N` → `mktemp` による衝突回避 + 権限保護（chmod 600）付き一時ファイル生成

## Impact

- `plugins/twl/commands/issue-spec-review.md`（直接変更）
- `plugins/twl/scripts/spec-review-manifest.sh`（命名規則確認）
- `.specialist-spawned-*.txt` / `.specialist-manifest-*.txt` を参照する可能性のある全スクリプト・コマンドファイル
- `tests/` に並列起動テスト追加
