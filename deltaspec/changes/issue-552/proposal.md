## Why

`plugins/twl/skills/co-autopilot/SKILL.md` の本文行数が 291 行（frontmatter 19 行除く）で、`ref-practices.md` L200 で定義された 200 行 CRITICAL 制限を超過している。Step 4 のインライン実装（ScheduleWakeup ポーリングループ・stagnation 検知・Silence heartbeat）と documentation セクション（state file 解決ルール・chain 停止時の復旧手順・不変条件記述）が肥大化の主因であり、SSOT 原則にも違反している。

## What Changes

- 新規 atomic `plugins/twl/commands/autopilot-pilot-wakeup-loop.md` を作成し、Step 4 の orchestrator 委譲・PHASE_COMPLETE 検知・stagnation 検知・Silence heartbeat ロジックを移動
- co-autopilot SKILL.md Step 4 を atomic 呼出に書き換え（98 行のインライン実装 → 委譲 1 行）
- Step 4.5 を narrative から atomic 委譲形式に統一（各 atomic の Read → 実行 は残し、説明文を削除）
- documentation 3 セクション（chain 停止時の復旧手順・state file 解決ルール・不変条件）を `architecture/domain/contexts/autopilot.md` に移動または統合、SKILL.md にはリンクのみを残す
- `deps.yaml` に新 atomic を追加（spawnable_by: [controller]）、co-autopilot.calls に追記
- `twl update-readme` 実行

## Capabilities

### New Capabilities

- **autopilot-pilot-wakeup-loop** atomic: ScheduleWakeup ベースの PHASE_COMPLETE 検知ループ、Worker stagnation 検知（`AUTOPILOT_STAGNATE_SEC`）、Silence heartbeat（5 分閾値）、input-waiting パターン検知、状況精査モード（30 分タイムアウト後）

### Modified Capabilities

- **co-autopilot Step 4**: inline 実装 → `autopilot-pilot-wakeup-loop` atomic への委譲（行数大幅削減）
- **autopilot.md**: Recovery Procedures セクション新規追加、State Management セクション強化、Constraints/Invariants セクション更新

## Impact

- `plugins/twl/skills/co-autopilot/SKILL.md`: 本文 291 行 → 200 行未満に削減
- `plugins/twl/commands/autopilot-pilot-wakeup-loop.md`: 新規作成
- `plugins/twl/architecture/domain/contexts/autopilot.md`: Recovery Procedures / State Management / Constraints セクション追記
- `plugins/twl/deps.yaml`: autopilot-pilot-wakeup-loop 追加
