## Why

現在14箇所以上で `git branch --show-current` から Issue 番号を抽出し IS_AUTOPILOT を判定しているが、この方式は CWD リセット時に正しく動作しない脆弱な設計であり、defense in depth として state file（issue-{N}.json）/ AUTOPILOT_DIR ベースの CWD 非依存判定に統一する必要がある。

## What Changes

- `extract_issue_num()` を廃止し、state file スキャンを主軸とする `resolve_issue_num()` 関数を新設
- `scripts/chain-runner.sh` の Issue 番号取得を `resolve_issue_num()` に置換
- `scripts/hooks/post-skill-chain-nudge.sh` の Issue 番号取得を `resolve_issue_num()` に置換
- `refs/ref-dci.md` の DCI 標準パターンを state file ベースに更新（git branch はフォールバックに格下げ）
- SKILL.md 群（workflow-setup, workflow-test-ready, workflow-pr-cycle）の bash スニペットを統一パターンに更新
- commands（merge-gate, all-pass-check, ac-verify, self-improve-propose）の DCI コンテキストを更新

## Capabilities

### New Capabilities

- **`resolve_issue_num()` 関数**: AUTOPILOT_DIR が設定されている場合 `$AUTOPILOT_DIR/issues/issue-*.json` をスキャンして `status=running` の Issue 番号を取得。複数 running 時は最小番号を採用。0 件時は `git branch --show-current` にフォールバック。壊れた JSON はスキップ（stderr 警告）

### Modified Capabilities

- **IS_AUTOPILOT 判定**: state file スキャン優先 → git branch フォールバックの優先度順に統一
- **Issue 番号解決**: 全 chain コンポーネント・コマンドで `resolve_issue_num()` を使用する統一パターン

## Impact

- `scripts/chain-runner.sh` — `extract_issue_num()` を `resolve_issue_num()` に置換
- `scripts/hooks/post-skill-chain-nudge.sh` — Issue 番号取得ロジック変更
- `refs/ref-dci.md` — DCI 標準パターン更新
- `skills/workflow-setup/SKILL.md` — bash スニペット更新
- `skills/workflow-test-ready/SKILL.md` — bash スニペット更新
- `skills/workflow-pr-cycle/SKILL.md` — bash スニペット更新
- `commands/merge-gate.md` — DCI コンテキスト更新
- `commands/all-pass-check.md` — DCI コンテキスト更新
- `commands/ac-verify.md` — DCI コンテキスト更新
- `commands/self-improve-propose.md` — DCI コンテキスト更新
