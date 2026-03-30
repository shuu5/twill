## Why

Phase 1+2 で全17 Issue を実装・マージ済みだが、その後のコマンド形式リファクタ（COMMAND.md → \<name\>.md）により、テストスイート（74件: 37 bats + 37 scenario）の実行結果が未確認。失敗テストの放置はリグレッションの見逃しにつながる。

## What Changes

- テストスイート全体のベースライン記録（現在の PASS/FAIL 数を Issue コメントに記録）
- 失敗テストの原因分析と修正（10件以下なら本変更で対応）
- hooks（PostToolUseFailure）の動作確認
- `chain generate --check` の実行と PASS 確認

## Capabilities

### New Capabilities

- なし（既存テストの修正のみ）

### Modified Capabilities

- 失敗しているテストケースの修正により、テストスイート全体が PASS する状態を回復

## Impact

- `tests/` 配下のテストファイル（.bats, scenario）
- テスト対象のコマンド・スキル・エージェント定義ファイル
- hooks 設定（`.claude/settings.json` の PostToolUseFailure）
- `chain generate --check` で検証される chain 定義
