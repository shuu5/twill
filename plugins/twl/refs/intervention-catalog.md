---
type: reference
spawnable_by: [controller, workflow, atomic]
can_spawn: []
---

# Intervention Catalog

Supervisor の介入判断ルール定義。6 つの介入パターンを Auto/Confirm/Escalate の 3 層に分類する。

## 3 層分類の判断基準

| 層 | 判断基準 | 実行者 |
|----|----------|--------|
| **Layer 0: Auto** | Worker が明確な失敗状態（status=failed）かつ回復手順が確立されている | Supervisor が自動実行 |
| **Layer 1: Confirm** | 状態が曖昧または複数の回復戦略が存在する | ユーザー確認後に実行 |
| **Layer 2: Escalate** | Supervisor 自身では判断不能、または影響範囲が広い | ユーザーに委譲（実行しない） |

**未知パターンのフォールバック**: カタログ外パターンは自動的に Layer 2 Escalate 扱いとし、カタログ拡張を self-improve Issue として提案する。

---

## 介入決定木

```
観察: status / PR / idle-time / branch-state
        ↓
検出: いずれかのパターンに一致するか？
        ├─ 一致なし → Layer 2 Escalate（フォールバック）+ カタログ拡張提案
        └─ 一致あり → 層分類へ
                ↓
分類: Auto / Confirm / Escalate
        ├─ Auto     → 前提条件を確認 → 自動修復 → InterventionRecord 記録
        ├─ Confirm  → ユーザーに意図を提示 → 承認後に実行 → 記録
        └─ Escalate → ユーザーに情報提供 → Issue 化推奨 → 実行しない
```

---

## Layer 0: Auto

### パターン 1: non_terminal_chain_end 回復

- **検出条件**: `worker-terminal-guard.sh` が `status=failed` + `failure.message="non_terminal_chain_end"` を書き込んだ場合
- **修復手順**:
  1. `state → running`（python3 -m twl.autopilot.state write ... --set status=running）
  2. `state → merge-ready`（`--force-done` 相当）
  3. `gh pr list` で PR 存在確認
  4. `autopilot-mergegate merge --force` 実行
- **前提条件**: PR が存在すること（`gh pr list --head <branch>` で確認）
- **リスク評価**: 低（merge-gate の品質チェックは通過済み前提）
- **事後**: InterventionRecord を `.observation/` に記録

### パターン 2: Worker PR 未作成

- **検出条件**: `status=running` だが `current_step=complete`、かつ `pr_url=null`
- **修復手順**:
  1. `gh pr list --head <branch>` で二重確認
  2. PR が本当に存在しない場合: `gh pr create --base main --head <branch> --title "..." --body "Closes #<issue>"`
- **前提条件**: worktree が存在すること、branch に commit があること
- **リスク評価**: 低（PR 作成は非破壊的操作）
- **事後**: InterventionRecord 記録 + PR URL を state に書き込み

### パターン 7: Worker idle 検知（state stagnate + 完了シグナル）

- **検出条件**: 以下の両方を満たす場合:
  1. `.autopilot/issues/issue-*.json` の `updated_at` が `AUTOPILOT_STAGNATE_SEC`（デフォルト 600s）以上古い
  2. 対象 Worker pane の tail に `>>> 実装完了:` を含む文字列が検出される
- **修復手順**:
  1. `session-comm.sh capture <window>` で Worker window の現在状態を確認
  2. issue 番号を特定し、`/twl:workflow-pr-verify --spec issue-<N>` を対象 Worker window に inject
- **前提条件**: tmux window が存在すること、`>>> 実装完了:` の issue 番号が特定できること
- **リスク評価**: 低（Worker は実装完了済みであり、pr-verify の起動は非破壊的操作）
- **事後**: InterventionRecord を `.observation/` に記録
- **部分一致フォールバック**: state stagnate のみで `>>> 実装完了:` が確認できない場合は **パターン4（Layer 1 Confirm: Worker 長時間 idle）** として処理する

---

## Layer 1: Confirm

### パターン 4: Worker 長時間 idle

- **検出条件**: `status=running` だが `last_active` が 15 分以上前、かつ tmux pane への出力がない
- **選択肢（ユーザーに提示）**:
  - A. nudge 送信（tmux send-keys でプロンプトを再送）
  - B. state を強制リセット（`--force-done` or `status=failed`）
  - C. 待機継続（5 分延長）
- **前提条件**: tmux window が存在すること
- **リスク評価**: 中（Worker が長時間処理中の可能性があるため強制操作はリスクあり）
- **事後**: 選択に応じた操作 + InterventionRecord 記録

### パターン 5: Wave 再計画

- **検出条件**: Phase 内の依存関係変更・優先度変更・新規 Issue 追加により、現行の Wave 計画が陳腐化した場合
- **選択肢（ユーザーに提示）**:
  - A. 現行 Wave を継続し、次 Wave で対応
  - B. 現行 Wave を中断し再計画
  - C. 新規 Issue を既存 Phase に追加
- **リスク評価**: 中（進行中の Worker への影響を考慮する必要がある）
- **事後**: 承認された計画変更を autopilot state に反映 + 記録

---

## Layer 2: Escalate

### パターン 3: コンフリクト解決 rebase

- **検出条件**: `git merge` または `git rebase` が conflict で失敗、または PR が "mergeable=false" 状態
- **情報提供内容**:
  - conflict ファイルの一覧
  - 推奨 rebase コマンド: `git fetch origin && git rebase origin/main`
  - 影響する Worker の branch 名
- **実行制約**: Supervisor は実行しない。ユーザーが手動で対処
- **リスク評価**: 高（コンフリクト解消には意味的理解が必要、誤解消で main 整合性が破壊される可能性）
- **事後**: ユーザーによる解消後に Worker を再起動するか確認

### パターン 6: 根本的設計課題・ADR 変更要

- **検出条件**: 以下のいずれか:
  - 複数 Worker に影響する設計上の問題が発見された
  - ADR 変更が必要な根本的な設計課題が発見された
  - main ブランチの整合性破壊リスクが検出された
- **情報提供内容**:
  - 問題の詳細説明
  - 影響を受けるコンポーネント一覧
  - 推奨アクション（Issue 化、ADR 起草、一時凍結）
- **実行制約**: Supervisor は実行しない。Issue 化を推奨
- **リスク評価**: 高（影響範囲が広い。誤った修正は複数 Issue に影響する）

---

## InterventionRecord 形式

`.observation/interventions/YYYYMMDD-HHMMSS-<pattern-id>.json` に保存:

```json
{
  "timestamp": "2026-04-09T12:00:00Z",
  "pattern_id": "pattern-1-non-terminal-recovery",
  "layer": "auto",
  "issue_num": 42,
  "branch": "feat/42-example",
  "action_taken": "force-done + merge-gate",
  "result": "success",
  "notes": ""
}
```
