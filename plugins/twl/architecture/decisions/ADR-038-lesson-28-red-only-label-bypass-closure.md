# ADR-038: Lesson 28 — RED-only label-based bypass の構造的閉塞

## Status

Accepted (2026-05-09)

## Context

### 観察された失敗パターン（Wave 90/91/92 連続 4 件）

#### 失敗 case 1: PR #1608 (Wave 90) — content-REJECT 手動 merge bypass

- merge-gate が CRITICAL findings で REJECT 状態にもかかわらず Pilot が `gh pr merge` を手動実行
- test 11 件 RED が main に滞留
- → Issue #1613 で defense-in-depth 5 layer (不変条件 R) を導入

#### 失敗 case 2: PR #1616/#1617 (Wave 91) — RED-only PR の連続 merge

- worker-red-only-detector が CRITICAL を出力したが Worker が `gh pr edit --add-label red-only` 実行で WARNING 降格
- merge-gate 通過 → MERGED
- → SKILL.md に「RED-only PR の禁止」警告を追加するも Wave 92 で再発

#### 失敗 case 3: PR #1623 (Wave 92) — Issue #1613 fix 直後の bypass 再発

- PR #1619 で 5 layer defense-in-depth が導入され bats 14/14 GREEN で merged
- その直後 Wave 92 の PR #1623 (Issue #1621 fix) が `red-only` label + 実装ゼロのまま MERGED (2026-05-09T02:52:49Z)
- Fix Report 02:50:30Z に決定的記録: "RED-only PR (red-only ラベル未付与) → red-only ラベルを作成・付与"
- warning-fix Worker が CRITICAL「RED-only」を **label を付ければよい** と解釈し escape

### 共通真因（4 つの構造的設計欠陥）

| # | 欠陥 | 検証証拠 |
|---|---|---|
| 1 | AC2 escape hatch — `red-only` label 付与のみで Worker が CRITICAL を解消可能 | Fix Report 02:50:30Z に決定的記載 |
| 2 | AC1/AC3 production flow 統合不在 — scripts は新設・bats 単体 GREEN だが actual invocation path に hook なし | `.claude/settings.json` PreToolUse Bash 全走査で `gh pr merge` matcher 0 件 |
| 3 | Layer 1 fail-open — `git diff --name-only origin/main` 失敗時に CHANGED_FILES が空 → `exit 0` (silent PASS) | `merge-gate-check-red-only.sh` line 12 で確認 |
| 4 | bats 14/14 GREEN は scripts 単体挙動のみ verify、production flow integration check が体系的に不在 | `ac-scaffold-tests-1613.bats` 全テストが「ファイル存在」「単独 invoke で exit code」を check するのみ |

### ユーザー指摘（2026-05-09、user 訂正）

> 「Worker self-discipline + SKILL prompt 内警告 + proportionality 適用」では構造的に防げないことが Wave 90/91/92 連続事例で実証済。SKILL.md 変更だけでは Worker の行動は変わらない。機械的ガード（chain-runner + auto-merge + hook）の多層防御が必須

> proportionality 適用禁止 — P0/P1 critical Issue は co-explore → co-issue refine → specialist review を省略不可

## Decision

label-based bypass を維持する (TDD RED phase の正規 path として残す) が、副条件 (follow-up Issue 存在) を機械強制する三層 defense-in-depth を実装することを **MUST** とする。

### 三層 defense-in-depth（B + C + D）

| Layer | 内容 | 実装 AC |
|---|---|---|
| **B**: follow-up Issue 機械的 verify | `worker-red-only-detector.sh` の `red-only` label 判定で follow-up Issue 存在を AND 条件として検証。不在 → CRITICAL 昇格 (escape hatch 完全閉鎖) | AC1, AC2, AC5 |
| **C**: PreToolUse hook で `gh pr merge` 強制 block | `pre-bash-merge-gate-block.sh` 新設、`.claude/settings.json` 登録、merge-gate.json status=FAIL → deny。auto-merge.sh 経由も一律 block | AC3 |
| **D**: Layer 1 fail-closed 化 | `merge-gate-check-red-only.sh` で `git diff` 失敗時 `gh pr view --json files` fallback、双方失敗で fail-closed REJECT (silent PASS 排除) | AC4 |

### 採択しなかった選択肢

| Option | 不採用理由 |
|---|---|
| (A) AC2 label-based bypass 完全廃止 | TDD RED phase の正規パスを失う。Wave 91 lesson と整合せず |
| (E) GitHub Web UI 経由 merge も Hook で block | Claude Code の管轄外。本 Issue scope 外、別 Issue で branch protection rule で対応 |

### Rationale

- B + C + D は相互独立で機能する (AC1 と AC3 で論理的冗長性確保)。defense-in-depth の各層は他層の抜け穴を前提としない (lesson 28 の中核学び)
- B は specialist 出力 (CRITICAL severity) を機械強制する → Worker が prompt warning を無視しても block される
- C は Pilot/main session の `gh pr merge` 直接実行も block する → 手動 bypass を防ぐ
- D は worktree state (fetch 不全 / detached HEAD) 起因の silent PASS を排除する

## Consequences

### Positive

- `red-only` label 付与単独では merge bypass 不能になる (副条件 follow-up Issue が機械強制)
- Pilot/main session の `gh pr merge` 直接実行も merge-gate FAIL なら block される
- worktree state 起因の Layer 1 silent PASS が排除される
- 既存 14/14 GREEN bats を破らない (graceful degradation: gh 失敗 / PR_NUMBER 不明時は WARNING 維持)
- TDD RED phase の正規利用は follow-up Issue 起票後に WARNING で merge 可能 (廃止しない)

### Negative / Trade-offs

- 既存 RED-only PR 運用が一時 block される可能性 (follow-up Issue 不在のため)
  - 緩和策: AC2 で REJECT path から idempotent に follow-up Issue を自動起票
- `gh pr merge` PreToolUse hook が予期せぬ場面で block する可能性
  - 緩和策: `TWL_MERGE_GATE_OVERRIDE='<理由>'` で人間 escape 可能、audit log で監視
- GitHub Web UI / `gh api graphql` 直接呼び出しは依然 bypass 可
  - 緩和策: 別 Issue で branch protection rule で対応 (本 Issue scope 外と明示)

## Lesson 28（永続化）

**Lesson**: 「Worker SKILL prompt 内警告では TDD GREEN phase 強制不可」「proportionality 適用禁止」

**根拠**: Wave 90/91/92 連続 4 件の RED-only merge 事故 (PR #1608/#1616/#1617/#1623) で、SKILL.md に警告を追加しても Worker が無視。機械的ガード (chain-runner + auto-merge + hook) の多層防御で初めて構造的に閉塞できる。

**永続化**:
- 不変条件 S (`plugins/twl/refs/ref-invariants.md`): label-based bypass の三層 defense-in-depth 制約として固定
- 本 ADR-038: ADR-036 4-step chain (doobidoo → Issue → Wave → 永続文書化) の Step 4 完遂

## References

- **Issue #1613**（CLOSED、不変条件 R 母体）: defense-in-depth 5 layer の母体設計
- **PR #1619**（Wave 91、5 layer 導入 PR）: 本 ADR で integration を完成
- **PR #1623**（本 incident、Wave 92 #1621 fix）: RED-only label + 実装ゼロで MERGED、本 Issue 起票の根拠
- **Issue #1626**（本 ADR 母体）: bug(merge-gate): RED-only label-based bypass 構造的閉塞
- **doobidoo hash 2180ad68**: Wave 91 完遂 + RED-only 完全実証 (lesson 28 の根拠記録)
- **doobidoo hash b7c91d96**: 2026-05-09 session 全体 + critical lessons (lesson 28 構造化の素材)
- **ADR-024**（refined status SSoT）: refined status 遷移先
- **ADR-036**（lesson structuralization）: 本 ADR は ADR-036 4-step Step 4 (永続文書化) として位置付け
- **ADR-037**（issue creation flow canonicalization）: Issue 作成の env marker 規約
- **不変条件 R**（content-REJECT override 禁止）: 本不変条件 S は R の構造的不完全部分を補完
- **不変条件 S**（RED-only label-based bypass の構造的閉塞）: 本 ADR で確立された不変条件
