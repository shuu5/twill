---
type: reference
spawnable_by: [controller, workflow, atomic, supervisor]
can_spawn: []
---

# Intervention Catalog

Supervisor の介入判断ルール定義。Wave 1-5 の実績を反映した介入パターンを Auto/Confirm/Escalate の 3 層に分類する。

## 3 層分類の判断基準

| 層 | 判断基準 | confidence | reversibility | blast-radius | 実行者 |
|----|----------|-----------|---------------|--------------|--------|
| **Layer 0: Auto** | 回復手順が確立済みで結果が予測可能 | 高（過去実績あり） | 高（元に戻せる） | 低（単一 Issue/PR 範囲） | Supervisor が自動実行 |
| **Layer 1: Confirm** | 手順は既知だが副作用・意図確認が必要 | 中（状況依存） | 中（一部不可逆） | 中（複数コンポーネント影響可） | ユーザーに報告後に実行 |
| **Layer 2: Escalate** | 意味的判断・設計判断が必要 | 低（不確実性高） | 低（破壊的操作含む） | 高（main・複数 Worker 影響） | ユーザーに委譲（実行しない） |

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

### パターン 8: Pilot auto-merge stall → 手動 squash-merge（Wave 1-5 実績）

- **Wave 実績**: Wave 1-5 で Pilot auto-merge stall 率 92%（9 PR 連続）。observer が手動 squash-merge を代行した実績に基づき Auto 層に追加
- **検出条件**: PR が "merge-ready" 状態で 10 分以上マージされない、かつ `gh pr view <N> --json mergeStateStatus` が `CLEAN` であること
- **修復手順**:
  1. `gh pr view <N> --json mergeStateStatus,mergeable` でマージ可能状態を確認
  2. `gh pr merge <N> --squash --auto` を実行
- **前提条件**: PR が CLEAN 状態かつ全 CI チェック通過済みであること
- **リスク評価**: 低（squash-merge は merge-gate 通過済み前提、reversible = git revert 可）
- **事後**: InterventionRecord を `.observation/` に記録

### パターン 9: session-comm.sh inject による数字応答（confirmation プロンプト解消）

- **Wave 実績**: Worker の confirmation プロンプト（`[y/N]` 等）待機でセッションが停止するケースに対応
- **検出条件**: Worker pane の tail に `[y/N]` / `[Y/n]` / `Enter to continue` 等のインタラクティブプロンプトが検出される
- **修復手順**:
  1. `session-comm.sh capture <window>` でプロンプト内容を確認
  2. プロンプトが既定の yes/Enter 応答で安全と判断できる場合: `session-comm.sh inject <window> "y"` または `session-comm.sh inject <window> ""` を実行
- **前提条件**: プロンプトが Worker の通常フロー（ツールインストール、軽微な確認）であること。認証・権限昇格プロンプトは Layer 2 Escalate
- **リスク評価**: 低（自動応答の内容が明確な場合のみ適用）
- **事後**: InterventionRecord を `.observation/` に記録

### パターン 10: tmux send-keys Enter によるキュー送信

- **Wave 実績**: Worker が Enter 待機状態でフローが止まるケースに対応
- **検出条件**: Worker pane が Enter 入力待ちで停止しており、`session-comm.sh capture` でアイドル状態を確認
- **修復手順**:
  1. `session-comm.sh capture <window>` で現在の pane 状態確認
  2. `tmux send-keys -t <target-pane> "" Enter` を実行
- **前提条件**: pane が正規のワークフロー内で Enter 待機していること（エラー画面・対話型エディタは対象外）
- **リスク評価**: 低（Enter 送信のみ。破壊的操作なし）
- **事後**: InterventionRecord を `.observation/` に記録

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

### パターン 11: merge-gate merge --force（ユーザーに報告後実行）

- **Wave 実績**: mergegate の force 実行は Wave 1-5 で Confirm 層として安定運用済み
- **検出条件**: merge-gate が non-blocking 状態（品質警告はあるが blocking エラーなし）で長時間停止、または operator がアンブロックを要求
- **ユーザーへの報告内容**:
  - merge-gate の非 blocking 警告一覧
  - `autopilot-mergegate merge --force` を実行する旨
- **修復手順**: ユーザー承認後 `autopilot-mergegate merge --force` を実行
- **前提条件**: blocking エラーがないこと（blocking エラーがある場合は Layer 2 Escalate）
- **リスク評価**: 中（警告を無視してマージするため、意図確認が必要）
- **事後**: InterventionRecord を `.observation/` に記録

### パターン 12: spec-review-session-init.sh pre-seed 経由 bypass（ユーザーに報告後実行）

- **Wave 実績**: Layer D refined-label-gate 6 連続 permission 拒否の回避手段として `spec-review-session-init.sh` pre-seed が使用された実績
- **検出条件**: Layer D の refined-label-gate で Claude Code classifier permission deny が発生し、pre-seed bypass が有効であることが確認できる場合
- **ユーザーへの報告内容**:
  - permission deny の内容
  - `spec-review-session-init.sh` 経由での bypass を行う旨
- **修復手順**: ユーザー承認後 `spec-review-session-init.sh` を pre-seed オプションで実行
- **前提条件**: bypass が承認された操作範囲内であること
- **リスク評価**: 中（classifier の判断を override するため意図確認必須）
- **事後**: InterventionRecord を `.observation/` に記録。bypass 経緯を doobidoo に `observer-lesson` タグで保存

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

### パターン 13: Claude Code classifier permission deny 2 回以上 → 即時 STOP（W5 連携）

- **Wave 実績**: Wave 5 で Layer D refined-label-gate が 6 連続 permission 拒否。classifier の判断を無視した継続が問題を拡大させた教訓
- **検出条件**: 同一セッション内で Claude Code classifier（`[PERMISSION-PROMPT]` イベント / `cld-observe-any`）が **同一カテゴリの操作を 2 回以上拒否**した場合
- **即時 STOP ルール**: 2 回目の deny を検出した時点で **全自律介入を即時停止**し、AskUserQuestion で状況を報告する
- **AskUserQuestion 報告内容**:
  - 拒否された操作の内容（1 回目・2 回目）
  - 拒否カテゴリ（例: file-write, bash-exec, etc.）
  - 推奨アクション（permission 設定確認、bypass 手順確認、Issue 化）
- **実行制約**: 2 回目以降は Supervisor も実行しない。ユーザーが permission 設定を確認・調整するまで停止
- **リスク評価**: 高（classifier の繰り返し拒否は設計上の問題を示唆する可能性がある）
- **事後**: InterventionRecord を `.observation/` に記録。経緯を doobidoo に `observer-intervention` タグで保存

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
