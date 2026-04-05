## Why

autopilot Worker が不変条件C（Worker マージ禁止）と不変条件B（Worktree 削除 Pilot 専任）に違反して PR を直接マージし、worktree を自分で削除できる状態にある。`auto-merge.md` に autopilot 配下判定がなく、`merge-gate-execute.sh` に CWD ガードがなく、`all-pass-check.md` に autopilot 配下での merge-ready 宣言ロジックがない。実際に Worker #43 が PR #57 を直接 squash merge し、worktree を自分で削除した事例が発生している。

## What Changes

- `commands/auto-merge.md`: autopilot 配下（issue-{N}.json status=running）判定を追加。該当時は merge/worktree 削除を実行せず、state-write で merge-ready に遷移のみ
- `scripts/merge-gate-execute.sh`: CWD ガード追加。worktrees/ 配下からの実行を拒否
- `commands/all-pass-check.md`: autopilot 配下時に state-write で merge-ready 宣言を行うロジック追加

## Capabilities

### New Capabilities

- **autopilot 配下判定**: auto-merge / all-pass-check が issue-{N}.json の status を参照し、autopilot 配下かどうかを判定
- **CWD ガード**: merge-gate-execute.sh が worktrees/ 配下からの実行を検知して拒否

### Modified Capabilities

- **auto-merge.md**: autopilot 配下時は merge-ready 宣言のみに制限（merge/cleanup を Pilot に委譲）
- **all-pass-check.md**: autopilot 配下時に merge-ready 遷移を実行
- **merge-gate-execute.sh**: 実行前に CWD を検証

## Impact

- 影響ファイル: `commands/auto-merge.md`, `scripts/merge-gate-execute.sh`, `commands/all-pass-check.md`
- 依存: `scripts/state-read.sh`, `scripts/state-write.sh`（既存、変更なし）
- 関連 Issue: #47（--auto フラグ廃止）、#54（state-write 構文修正）
