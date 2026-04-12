## Why

Issue #438 の AC#5「setup → test-ready → pr-verify の chain 遷移が自動的に完了する」が PR diff 内で証明されていない。Wave 1-5 の実稼働で `non_terminal_chain_end` および Pilot の PHASE_COMPLETE wait stall が複数回発生しており、chain 遷移の正常動作を保証する E2E テストと証跡が欠如している。

## What Changes

- `cli/twl/tests/autopilot/` に integration test を追加し、setup → test-ready → pr-verify の chain 遷移を検証する
- autopilot 実稼働での `.autopilot/trace/inject-*.log` キャプチャを PR コメントに記録するメカニズムを追加する
- chain 遷移が 0 inject-skip で成立することを確認する検証スクリプトを追加する

## Capabilities

### New Capabilities

- **E2E chain 遷移 integration test**: `cli/twl/tests/autopilot/` 配下に、setup chain 完了 → state `workflow_done=setup` 書き込み → orchestrator 検知 → inject_next_workflow 呼び出し → test-ready → pr-verify chain 到達を検証するテストを追加
- **trace ログ PR 添付スクリプト**: autopilot 実稼働で生成される `inject-*.log` を 1 Wave 分キャプチャし、PR コメントに添付するユーティリティ

### Modified Capabilities

- なし（証跡追加・テスト追加のみ）

## Impact

- 対象: `cli/twl/tests/autopilot/` （新規テストファイル追加）
- 依存: Issue #469（non_terminal_chain_end 修正）、Issue #472（PHASE_COMPLETE wait stall 修正）が解決済みであること
- 既存コードへの変更なし（テスト・ログキャプチャのみ）
