## Context

`co-autopilot/SKILL.md` の本文が 291 行（CRITICAL 制限 200 行）に達している。主要因は:

1. **Step 4（98 行）**: `nohup/disown`・ScheduleWakeup ポーリングループ・stagnation 検知・Silence heartbeat がインライン記述されている
2. **Step 4.5（13 行）**: narrative 形式（各 atomic の説明文が冗長）
3. **documentation 3 セクション（計 ~55 行）**: state file 解決ルール・chain 停止時の復旧手順・不変条件記述が SSOT（autopilot.md）と重複

既存の `architecture/domain/contexts/autopilot.md` には Constraints セクション（不変条件 A〜M）と State Management 情報が存在するが、Recovery Procedures（復旧手順）は未記載。

## Goals / Non-Goals

**Goals:**

- co-autopilot SKILL.md の本文を 200 行未満に削減（Acceptance Criteria）
- Step 4 ロジックを新規 atomic `autopilot-pilot-wakeup-loop` に委譲
- documentation セクション 3 種を autopilot.md へ移動し SSOT を確立
- deps.yaml・update-readme・twl --check 全通過

**Non-Goals:**

- ScheduleWakeup / stagnation 検知ロジック自体の動作変更
- co-autopilot 以外の controller の行数削減
- autopilot.md の全面リライト（追記・整理のみ）

## Decisions

### 1. 新規 atomic: `autopilot-pilot-wakeup-loop`

**配置**: `plugins/twl/commands/autopilot-pilot-wakeup-loop.md`  
**type**: atomic  
**spawnable_by**: [controller]  
**責務**: orchestrator 起動 → ScheduleWakeup(300) ポーリング → PHASE_COMPLETE 検知 → stagnation 検知 → Silence heartbeat → 状況精査モード（30 分タイムアウト後）

**移動する内容（SKILL.md Step 4 L88-L186）**:
- nohup/disown コマンドブロック（orchestrator 起動）
- ScheduleWakeup ベースの wake-up ループ（手順 1-4）
- Silence heartbeat（全 Worker updated_at 5 分無変化時の処理）
- 状況精査モード（MAX_WAIT_MINUTES=30 超過後の処理）

### 2. Step 4 の書き換え

**変更前**: 98 行のインライン実装  
**変更後**: `commands/autopilot-pilot-wakeup-loop.md` を Read → 実行（委譲形式、~5 行）

### 3. Step 4.5 の書き換え

**変更前**: narrative 形式（各 atomic の処理を説明する文章）  
**変更後**: atomic 委譲形式（`commands/<name>.md を Read → 実行` のみ、説明文を削除）

### 4. documentation 外部化

| SKILL.md セクション | 移動先 | 方針 |
|---|---|---|
| state file 解決ルール（L228-245、18 行） | autopilot.md「State Management」セクション補記 | 既存セクションに統合 |
| 不変条件（L247-252、6 行） | autopilot.md「Constraints」セクション（既存、参照のみ残す） | SKILL.md には 1 行リンクのみ残す |
| chain 停止時の復旧手順（L253-285、33 行） | autopilot.md「Recovery Procedures」セクション新規追加 | SKILL.md には 1 行リンクのみ残す |

### 5. deps.yaml 更新

```yaml
# 追加
autopilot-pilot-wakeup-loop:
  type: atomic
  spawnable_by: [controller]
  
# co-autopilot.calls に追加
  calls:
    - atomic: autopilot-pilot-wakeup-loop
```

## Risks / Trade-offs

- **リスク**: autopilot.md に復旧手順を移動することで、SKILL.md から直接参照できなくなる → 対策: SKILL.md にリンクを残す（Markdown リンク形式）
- **トレードオフ**: Step 4 を 1 つの atomic に委譲することで、Pilot の制御フローが atomic 内に隠れる → 許容（design principle P1 に準拠: Pilot の能動評価は atomic 経由限定）
- **bats smoke テスト**: autopilot 実行テストが完全ではない場合、新 atomic の動作を自動検証しにくい → 手動テスト + AC チェックで補完
