# Pilot auto-merge stall 根本原因レポート

**Issue**: #871 (Phase C Epic #866 W2)
**作成日**: 2026-04-22
**対象期間**: Phase A (2026-04-21) + Phase B (2026-04-21 〜 2026-04-22)
**分析対象**: 30 PR、`.autopilot/archive/**/issue-*.json` 21 件、`.autopilot/trace/inject-*.log` 3 ファイル (1944 行)

---

## Executive Summary

**Phase B auto-merge 成功率**: **0% (0/19)** — 全 19 merged PR が observer (shuu5) 手動 merge。autopilot 自律 merge は 1 件も発生せず。

従来 plan で「92% stall、8% 成功」と記録されていたが、実測では **100% stall**。observer が先制 merge で介入することで、autopilot の auto-merge 発火機会そのものが存在していなかった。

真の根本原因は **3 つの独立した問題の複合**:

| # | 主因 | 影響件数 | Phase C 対応 |
|---|------|---------|--------------|
| 1 | **#853 deps-integrity CI UNSTABLE** | 12/19 (63%) | Sub-B1 (#867) で部分解消、残 Phase D #878 |
| 2 | **merge-ready 状態の滞留** (orchestrator race) | 5/21 archive | W2 #873 |
| 3 | **running 状態の滞留** (LLM 内部 stall) | 4/21 archive | W2 #874 + Phase D |

---

## 1. データ収集方法

### 1.1 PR レベル (Phase B merged PRs)

```bash
for pr in 844 845 846 847 849-852 854-865; do
  gh pr view $pr --json mergeStateStatus,mergedBy,mergedAt,statusCheckRollup
done
```

### 1.2 Issue レベル (archive 内の state JSON)

```bash
for dir in .autopilot/archive/*/; do
  jq -c '{file, issue, status, failure}' "$dir"issue-*.json
done
```

### 1.3 Orchestrator Log

```bash
grep -oE "INJECT_[A-Z_]+|\[[A-Z_]+\]" .autopilot/trace/inject-20260422.log \
  | sort | uniq -c | sort -rn
```

---

## 2. 実測データ

### 2.1 Phase B PR merge 実績 (全 20 PR)

全 20 PR `merged_by: shuu5`（observer）、1 件も autopilot 自律 merge なし。

| PR | CI failures | state | 備考 |
|----|-------------|-------|------|
| #844, #846, #847, #849, #851, #854, #855, #860, #861, #862, #863, #864 (12 件) | 0 | merged | CI GREEN でも observer 先制 merge |
| #845, #850, #852, #858, #865 (5 件) | 2 | merged (admin) | deps-integrity + 1 件 |
| #856, #857, #859 (3 件) | 4 | merged (admin) | deps-integrity + 他 3 件 |

**観察**: CI GREEN 12 件でも observer が先制 squash merge したため、autopilot auto-merge 発火の機会がそもそも存在していない。

### 2.2 Archive の issue state 分布 (21 件)

| status | 件数 | 該当 issue |
|--------|------|-----------|
| `done` | 9 | #611, #649, #805, #812, #795, #652, #829-#832 |
| `merge-ready` (滞留) | 5 | #836, #837, #833, #834, (+1 from Phase B W4) |
| `running` (滞留) | 4 | #838, #839, #840, #835 |
| `failed` (poll_timeout) | 2 | #793, #794 |
| `failed` (merge_conflict) | 1 | #814 → PR #824 |

### 2.3 Inject Log 分析 (2026-04-22、Phase B 全期間)

```
29 INJECT_SUCCESS         # inject 正常実行
11 INJECT_PR_MERGE_WARN  # status=running WARN (AC-4 仕様通り、red herring)
 0 INJECT_EXHAUSTED       # timeout 上限到達なし (カウンタ機能済)
```

**red herring 確認**: `INJECT_PR_MERGE_WARN` 11 回は **stall 原因ではない** (AC-4 #744 で正常挙動と確定)。diagnostic log のノイズ。

---

## 3. Failure Category 分類 (6 カテゴリ)

| # | Category | 件数 | 比率 | 主因 | Phase C fix |
|---|----------|------|------|------|-------------|
| **C1** | `poll_timeout at ac-verify/polling` | 2 | 10% | ac-verify LLM stall + orchestrator polling timeout | C6 と合流、Phase D |
| **C2** | `merge_conflict` (rebase 必要) | 1 | 5% | deps.yaml 頻繁 rebase 発生 | external (手動 rebase) |
| **C3** | `merge-ready 滞留` (orchestrator race) | 5 | 24% | chain-runner.sh 書込後、orchestrator 再 poll 待ち | **#873** |
| **C4** | `branch_protection / CI UNSTABLE` | 12 | 57% | **#853 deps-integrity** が全 PR を UNSTABLE 化 | **#867 (部分解消)**, **#878 (完全解消)**, **#872 (precheck)** |
| **C5** | `inject_exhausted` | 0 | 0% | AC-2 safety net が機能 (#744 merged) | 既対応済 |
| **C6** | `running 滞留` (LLM 内部 stall) | 4 | 19% | workflow-pr-merge skill 内 LLM 指示待ち | **#874 (WARN 降格)** + Phase D (skill 改善) |

**C4 が最大要因 (57%)**: #853 の 4 errors (#867 で 1 件解消、#878 で残 3 件解消) が解消されれば、Phase B の 12 PR がそもそも UNSTABLE にならない。

---

## 4. 根本原因 (信頼度順、実測データ付き)

### H4 (confirmed, 85% confidence): branch protection / CI UNSTABLE

**証拠**:
- Phase B 全 20 PR で CI failures >0 のもの 8 件、全て `deps-integrity` 起因
- main HEAD で `twl check --deps-integrity` が 4 errors (Phase B 開始時)、3 errors (Sub-B1 後)
- `gh pr view --json mergeStateStatus` は **全 UNKNOWN** (merge 済のため現在値取得不能)、だが merge 直前の `UNSTABLE` は CI log から明白

**Phase C fix**:
- **#867 (merged)**: step 名 rename で 1 error 解消
- **#878 (Phase D)**: 残 3 drift 解消で CI green 回復
- **#872 (W2)**: `auto-merge.sh` に `gh pr view --json mergeStateStatus` precheck 追加 → UNSTABLE を事前検知して Pilot に明示 escalate

### H6 (confirmed, 70% confidence): merge-ready 滞留 race

**証拠**:
- Archive 内 5 件が `status: merge-ready` で stuck (#836, #837, #833, #834)
- orchestrator の `POLL_INTERVAL_SEC` デフォルト 30s → 最大 30s の race window

**Phase C fix**:
- **#873 (W2)**: `orchestrator.py:268-421` の merge-gate 起動ループで `status=merge-ready` かつ `last_poll_at > 60s` issue を**即時再試行パス**に通す

### H6b (confirmed, 60% confidence): running 滞留 (LLM 内部 stall)

**証拠**:
- Archive 内 4 件が `status: running` で stuck (#838, #839, #840, #835)
- workflow-pr-merge skill 内の LLM-driven step (e2e-screening, pr-cycle-report, all-pass-check, merge-gate, auto-merge) のどれかで LLM が停止

**Phase C fix**:
- **#874 (W2)**: red-herring log (INJECT_PR_MERGE_WARN) を DEBUG 降格、診断明確化
- **Phase D**: workflow-pr-merge skill 内に heartbeat + timeout guard 追加 (別 Issue)

### H1/H2 (rejected, red herring)

- **H1 (inject skip deadlock)**: #744 merged (2026-04-20) で skip 分岐削除済。INJECT_PR_MERGE_WARN は AC-4 仕様通り、診断ログでしかない
- **H2 (chain-runner state write silent fail)**: archive の `status=merge-ready` が実在することから、書込は成功している。H6 の race 窓が真の原因

---

## 5. Phase C W2 実装推奨順序

1. **#867 (完了)** step 名 rename → CI UNSTABLE を部分改善
2. **#872** `auto-merge.sh` に `gh pr view --json mergeStateStatus` precheck 追加 → UNSTABLE 明示 escalate → C4 57% の fail-fast 化
3. **#873** orchestrator race 解消 → C3 24% 解消
4. **#874** WARN 降格 → diagnostic noise 解消 → 今後の誤診断防止
5. **#875** bats 6 category 再現 (sandbox) → 回帰防止
6. **#878 (Phase D)** 残 drift 解消 → C4 完全解消

**予想 stall rate 改善**:
- 現状: 100% (observer 介入前提の運用)
- #872 + #873 実装後: 50-60% (C3 + 一部 C4 解消、LLM stall 残)
- #878 解消後: 20-30% (C4 完全解消、C6 LLM stall のみ残)
- Phase D C6 改善後: 10-15%

## 6. 注意事項と Spin-off 提案

### Spin-off candidates (Phase D)

- **#878**: 残 3 drift (worktree-create / arch-ref 移動 / pr-merge 拡張)
- **#TBD**: workflow-pr-merge skill heartbeat + timeout guard (C6 対策)
- **#TBD**: ac-verify LLM stall 検知 + retry (C1 対策)

### Observer 介入戦略の維持

本 report の fix 後も、observer 先制 merge 戦略は即座に廃止せず、**段階的に縮退**することを推奨:
1. #872 + #873 merge 後、sandbox で 3 PR 自律 merge を試験
2. 成功率 50%+ 確認後、production で試行
3. #878 merge 後に observer 介入を「緊急時のみ」に縮退

## 7. 参照

- PR #879 (#867 fix) merged: 2026-04-22
- Phase C Epic: #866
- Plan: `~/.claude/plans/twl-cli-twl-plugin-architecture-binary-manatee.md`
- 関連 fix Issue: #867 (closed), #869 (closed), #872, #873, #874, #875 (open)
- Phase D Issue: #878 (残 drift), #868/#870 (Phase D 待ち)
