## Context

`autopilot-launch.sh` はすでに `AUTOPILOT_DIR` を Worker プロセスへ渡している（L307-309, L365-366: `env AUTOPILOT_DIR=... cld ...`）。`autopilot-init.sh` L9 でも `AUTOPILOT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}"` により SSOT が確立されている。

問題は「実装済みだが検証されていない」状態であること。test-target worktree で co-autopilot を起動した際の env 継承パスが bats テストで未カバー。また `co-autopilot/SKILL.md` には state file 解決ルールが明文化されていない。

## Goals / Non-Goals

**Goals:**
- `autopilot-launch.sh` が Worker bash に `AUTOPILOT_DIR` を渡すことを bats テストで実証する
- `co-autopilot/SKILL.md` に「state file 解決ルール」セクションを追加し、`AUTOPILOT_DIR` SSOT と `autopilot-init.sh` L9 への参照を明文化する
- `AUTOPILOT_DIR=/tmp/foo` 設定時に Worker state が `/tmp/foo/issues/` へ書かれることを検証する

**Non-Goals:**
- 新規環境変数の導入（`AUTOPILOT_DIR` を SSOT として維持）
- `autopilot-init.sh` や state read/write スクリプトの変更（既存実装を信頼）
- `autopilotdir-state-split.bats` の既存テスト変更

## Decisions

1. **SKILL.md セクション追加のみ**: `co-autopilot/SKILL.md` の「不変条件」セクション直前に「state file 解決ルール」セクションを挿入。既存コードへの変更はしない。

2. **テスト戦略**: `autopilot-launch.sh` のテスト追加は mock 戦略を使用。tmux/cld 実際の起動は行わず、`--dry-run` または環境変数の構築ロジックを単体テストとして検証する。既存 `autopilot-launch-merge-context.bats` のパターンを参考にする。

3. **bats テストファイル**: 新規ファイル `autopilot-launch-autopilotdir.bats` を作成。`AUTOPILOT_DIR` 伝搬に特化したテストを追加する。

## Risks / Trade-offs

- `autopilot-launch.sh` は tmux/cld を必要とするため、実際の Worker 起動テストは困難。bats では mock またはコマンドライン引数構築の単体テストに留まる。
- 実際の「Worker プロセスでの `printenv AUTOPILOT_DIR` が一致する」という観測は E2E テストでのみ可能（#483 の範囲）。本 Issue では bats 単体テストで env 構築の正確性を検証する。
