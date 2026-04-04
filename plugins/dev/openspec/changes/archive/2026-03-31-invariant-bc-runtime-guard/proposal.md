## Why

autopilot Worker が不変条件C（Worker マージ禁止）と不変条件B（Worktree 削除 Pilot 専任）に違反して PR を直接マージし、worktree を自分で削除できる。Pilot のポーリングが Worker 完了を検知できず autopilot が破綻する。

## What Changes

- `commands/auto-merge.md`: autopilot 配下判定を追加。status=running 時は merge/worktree 削除をスキップし merge-ready 宣言のみ
- `scripts/merge-gate-execute.sh`: CWD ガード追加。worktrees/ 配下からの実行を拒否
- `commands/all-pass-check.md`: autopilot 配下で merge-ready 宣言ロジックを追加

## Capabilities

### New Capabilities

- autopilot 配下判定: issue-{N}.json の status=running を検出し、Worker の直接 merge を防止
- CWD ガード: merge-gate-execute.sh が worktrees/ 配下で実行された場合にエラー終了
- merge-ready 遷移: all-pass-check が autopilot 配下で state-write による status 遷移を実行

### Modified Capabilities

- auto-merge.md: 既存の merge/worktree 削除フローに autopilot 分岐を追加
- all-pass-check.md: テスト全パス時の後続処理に autopilot 配下パスを追加

## Impact

- 対象ファイル: `commands/auto-merge.md`, `commands/all-pass-check.md`, `scripts/merge-gate-execute.sh`
- 依存: `scripts/state-read.sh`, `scripts/state-write.sh`（既存 API を使用）
- autopilot 非配下（手動実行）時は既存動作に変更なし
