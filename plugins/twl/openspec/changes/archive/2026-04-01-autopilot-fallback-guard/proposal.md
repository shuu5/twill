## Why

autopilot 配下の Worker が `IS_AUTOPILOT=false` と誤判定した場合、不変条件C（Worker マージ禁止）のガードが機能せず、Worker が直接 `gh pr merge` を実行してしまう。現在のガード3層のうち第1層・第2層が同じ `state-read.sh` に依存しており、同時破壊されるリスクがある。独立した第4層ガードとして `issue-{N}.json` の存在チェックによるフォールバックを追加する。

## What Changes

- `commands/auto-merge.md` Step 0: `IS_AUTOPILOT` 判定後に `issue-{N}.json` 直接ファイル存在確認を追加（MODE=merge 冒頭で発動）
- `scripts/merge-gate-execute.sh`: Worker ロール（tmux window 名 `ap-#*`）からの merge 実行時に追加ガード
- `openspec/changes/invariant-bc-runtime-guard/specs/auto-merge-guard.md` に誤判定シナリオ追加
- 非 autopilot 通常利用への非影響テスト

## Capabilities

### New Capabilities

- `issue-{N}.json` 存在チェックによる独立した第4層フォールバックガード（state-read.sh とは独立）
- Worker ロール検出による merge-gate-execute.sh の追加ガード

### Modified Capabilities

- `auto-merge.md` Step 0: 既存の `IS_AUTOPILOT` 判定に加え、フォールバック検証ステップを追加
- `merge-gate-execute.sh`: tmux window 名パターン `ap-#*` による Worker ロール検出を追加

## Impact

- `commands/auto-merge.md`: フォールバックガード追加
- `scripts/merge-gate-execute.sh`: Worker ロール検出ガード追加
- `openspec/changes/invariant-bc-runtime-guard/specs/auto-merge-guard.md`: シナリオ追加
- 非 autopilot フロー: `issue-{N}.json` 不在 + `ISSUE_NUM` 未設定で既存動作維持（非影響）
