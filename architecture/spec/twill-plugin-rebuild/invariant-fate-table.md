# 不変条件 fate audit — 既存 A-S (19 件) 継承戦略 + 新規 T-X (5 件) 追加

> **目的**: 既存 `plugins/twl/refs/ref-invariants.md` の不変条件 A-S (19 件) を 1 件ずつ audit し、新 spec での fate (保全 / 強化 / 部分 Superseded / 削除) を決定。さらに本 spec で 9 P0 bug 分析から導出される新規不変条件 T-X (5 件) を追加。
>
> **drift 訂正**: `ref-invariants.md` L1 の「A-N (14 件)」記述は 19 件 (A-S) との不整合 = drift。新 spec 起票時に訂正課題。

---

## 集計

| fate | 件数 |
|---|---|
| 保全 (新 spec でも有効、変更なし) | 14 |
| 保全 (強化) (新 spec の機構でより強く enforce) | 3 |
| 部分 Superseded (一部 layer が新 spec で置換) | 2 |
| **新規追加 (T-X)** | 5 |

合計: 既存 19 件 + 新規 5 件 = **24 件 (A-X)**。

---

## 既存 不変条件 A-S fate

### 完全保全 (14 件)

| Inv | 主題 | 新 spec での扱い |
|---|---|---|
| A | 状態の一意性 (`issue-{N}.json` status 遷移) | 保全。`status` field の遷移パス制約は新 spec の Project Board status と整合 |
| C | Worker マージ禁止 (Pilot のみ merge 実行) | 保全 (強化版は別表記)。新 spec で auto-merge.yml + branch protection で機械化 |
| D | 依存先 fail 時の skip 伝播 | 保全。phase 設計でも依存解決ロジックは継承 |
| E | merge-gate リトライ制限 (最大 1 回) | 保全。step verification framework でも同様の retry policy |
| F | squash merge API 失敗時 rebase 禁止 | 保全 |
| H | deps.yaml コンフリクト時自動 rebase | 保全 |
| I | 循環依存拒否 | 保全 |
| J | merge 前 base drift 検知 | 保全 |
| L | autopilot マージ実行責務 (orchestrator 経由のみ) | 保全。Supervisor 観察介入例外 (#848) も継承 |
| N | Lesson Structuralization (4-step chain) | 保全。新 spec でも MUST (ADR-036) |
| O | session.json claude_session_id UUID v4 | 保全 |
| P | Issue 起票 flow 大原則 (co-explore precondition) | 保全。phase-explore の出力が precondition |
| Q | budget status line `(YYm)` format 解釈 | 保全。administrator polling cycle で参照 |
| R | content-REJECT override 禁止 | 保全。step verification の post-verify FAIL → merge block |

### 保全 (強化) (3 件)

| Inv | 主題 | 新 spec での強化点 |
|---|---|---|
| B | Worktree lifecycle Pilot 専任 | **強化**: 新 spec の 3 階層全層 tmux spawn 設計で、worker も自分の worktree 内で動作する前提が固まる。`spawn-tmux.sh` helper で「pilot が worker 用 worktree を事前作成、worker は使用のみ」を機械化 |
| G | クラッシュ検知保証 | **強化**: `crash-failure-mode.html` で worker/pilot/admin の 3 階層 crash 検知 + recovery を仕様化、SLA + 検知閾値を明示 |
| K | Pilot 実装禁止 | **強化**: 新 spec の pilot 責務 boundary 仕様で「pilot は worker を spawn / mail 集約 / status 遷移のみ、コード変更禁止」を SKILL.md MUST + step verification post-verify (src diff = pilot のみは fail) で機械化 |

### 部分 Superseded (2 件、新 spec で一部 layer 置換)

| Inv | 主題 | 部分 Superseded 内容 |
|---|---|---|
| M | chain 遷移は orchestrator / 手動 inject のみ | 新 spec で「chain」概念再設計: phase 遷移は Project Board status 更新 + PreToolUse gate hook で機械化。`inject_next_workflow` の概念廃止 (admin polling cycle が status 変化を検知して次 phase spawn)。orchestrator の bash inject 経路は廃止、ただし「Pilot 直接 nudge による bypass 禁止」原則は新 spec でも MUST として継承 |
| S | RED-only label-based bypass の構造的閉塞 (ADR-038) | 5 layer defense は保全、ただし新 spec の step verification framework (§6) で「RED test 追加 + post-verify で RED 確認 + green-impl で src diff 確認」が機械化されることで、`worker-red-only-detector.sh` の severity 判定 layer (Layer 1) が **構造的に不要** になる。残り 4 layer (follow-up Issue 自動起票 + PreToolUse hook block 等) は保全 |

---

## 新規追加 不変条件 T-X (本 spec で導出)

### 不変条件 T: file mailbox atomic write 必須

**目的**: 9 P0 bug の #1703 (phase-review.json cross-pollution) を構造的に不能化する。

**制約**:
- 全 mailbox write は **`flock` を取得した atomic write** を MUST とする
- mailbox path は `.mailbox/<session-name>/inbox.jsonl` の per-session 形式
- 共通 path への write は禁止 (横断要因 F-1 の構造的解消)
- mailbox write には必ず `{"from": "<sender>", "ts": "<iso8601>", ...}` を含める (sender tracking)

**根拠**: 9 P0 bug 分析の Bug #1703 lesson、横断要因 F-1。

**検証方法**: bats `file-mailbox-atomic-write.bats` (新規)、並列 write race condition test。

**影響範囲**:
- `plugins/twl/scripts/mailbox.sh` (新規 helper)
- 全 worker / pilot / administrator SKILL.md (mail write 経路)

### 不変条件 U: step verification post-verify 必須

**目的**: 9 P0 bug の #973 (RED merge silent rot)、L1873-1884 自己申告 step を構造的に不能化する。

**制約**:
- 全 chain step は **pre-check → exec → post-verify → report** の 4 phase lifecycle を MUST
- post-verify で機械検証 (test 数増加 / RED→GREEN / src diff / Agent return value 等) を **必ず実施**
- self-report-only (record_current_step + ok のみ) は禁止
- post-verify FAIL → step abort + pilot escalate (mail に failure 明記)

**根拠**: 9 P0 bug 分析の Bug #973 lesson、L1873-1884 自己申告 step 問題。

**検証方法**: bats `step-verification-post-verify.bats` (新規)、test なしで green-impl 呼び出すと step abort することを verify。

**影響範囲**:
- `plugins/twl/scripts/step.sh` (新規 framework)
- 全 worker SKILL.md (step_run 経由でのみ step 実行)

### 不変条件 V: per-Worker checkpoint path (共通 path 禁止)

**目的**: 9 P0 bug の #1703 (checkpoint cross-pollution) + #1673 (cleanup cross-Wave 破壊) を構造的に不能化する。

**制約**:
- 全 state / cleanup / checkpoint write は **per-Worker (issue_number / session_name) を含むパス** にデフォルト書き込み
- 共通パスへの write は明示的 `--shared` フラグ + audit log 必須
- cleanup スクリプトは `--scope <wave-id>` を必須引数とし、他 Wave のリソースに触れない

**根拠**: 9 P0 bug 分析の Bug #1703, #1673 lesson、横断要因 F-1。

**検証方法**: bats `per-worker-state-isolation.bats` (新規)、複数 Worker simulation で他 Worker の state を読み書きしないことを verify。

**影響範囲**:
- `cli/twl/src/twl/autopilot/checkpoint.py` の `_checkpoint_dir()` (per-issue 必須化、`--shared` 明示なしは fail)
- `plugins/twl/scripts/autopilot-cleanup.sh` (`--scope` 必須化、または完全廃止)

### 不変条件 W: PreToolUse hook で status gate 機械化

**目的**: 9 P0 bug の #1660 / #1662 / #1663 / #1684 (env var 経由 caller authz) を構造的に不能化する。

**制約**:
- phase-* invocation は **PreToolUse hook 経由で前提 status を verify** することを MUST
- bash env var (`TWL_CALLER_AUTHZ` 等) による caller authz は廃止
- gate hook は `phase-gate.sh` thin helper (~30 lines) で実装、status 不一致は exit 1 + administrator notify

**根拠**: 9 P0 bug 分析の Bug #1660/1662/1663/1684 lesson、横断要因 F-2。

**検証方法**: bats `phase-gate-hook.bats` (新規)、Refined でない Issue に phase-impl を呼び出すと deny されることを verify。

**影響範囲**:
- `plugins/twl/scripts/phase-gate.sh` (新規 helper)
- `.claude/hooks/phase-gate.json` (PreToolUse hook 設定)
- 既存 `TWL_CALLER_AUTHZ` 機構の廃止 (chain-runner.sh / observer-parallel-check.sh 等)

### 不変条件 X: deploy / verify セット必須 (daemon / watchdog)

**目的**: 9 P0 bug の #1687 (mcp-watchdog deploy 経路不在、5 ヶ月 5 回再発) を構造的に不能化する。

**制約**:
- 新規 daemon / watchdog 実装は **「起動 hook」+「起動確認テスト」セット** で merge することを MUST
- 起動 hook (session-start hook 等) と起動確認 test (bats で `ps` / `pgrep` 確認) を **同 PR 内に含む**
- N 回 (N≥2) 再発するバグは **修正ではなく root cause 分析** を required (epic / spike issue 化)

**根拠**: 9 P0 bug 分析の Bug #1687 lesson、横断要因 F-3。

**検証方法**: bats `daemon-deploy-verify-set.bats` (新規)、新規 watchdog 系 PR は起動 hook ファイルの追加を assert。

**影響範囲**:
- `.claude/hooks/` 配下の hook 登録規約
- `plugins/twl/tests/bats/` 配下の daemon verification test
- 新 spec の rebuild-plan.md (本 invariant を Phase 1 PoC の verify points に含める)

---

## ref-invariants.md drift 訂正課題

現状の `plugins/twl/refs/ref-invariants.md` L1:

```
twill autopilot システムの不変条件 A-N（14 件）の正典定義。
```

これは drift。実際は **A-S の 19 件** (O/P/Q/R/S が後から追加された)。新 spec 起票時に以下を訂正:

```diff
- twill autopilot システムの不変条件 A-N（14 件）の正典定義。
+ twill autopilot システムの不変条件 A-X（24 件）の正典定義。
+ (旧版は A-N 14 件 → A-S 19 件 → A-X 24 件 と段階的拡張、ADR-043 で T-X 5 件追加)
```

更新日も `2026-05-08` → `2026-05-12` に。

加えて、新規 invariant T-X の section を `ref-invariants.md` に追記する。新 spec の `invariant-fate-table.md` (本ファイル) は audit table、`ref-invariants.md` は正典定義として役割分担。

---

## 不変条件カバレッジ matrix (9 P0 bug → 不変条件)

| Bug | 既存 invariant | 新規 invariant T-X | カバー状況 |
|---|---|---|---|
| #1660 SKIP_*_REASON sanitize | (なし) | **W** (PreToolUse hook gate) | 新規 W で構造的解消 |
| #1662 OBSERVER_PARALLEL_CHECK_STATES `:-` | (なし) | **W** | 同上 |
| #1663 OBSERVER_PARALLEL_CHECK_STATES override | (なし) | **W** | 同上 |
| #1673 autopilot-cleanup cross-wave | B (worktree pilot 専任) | **V** (per-Worker checkpoint) | B 強化 + V で構造的解消 |
| #1674 orchestrator early-exit | M (chain 遷移制限) | **U** (step post-verify) | M 部分 Superseded + U で構造的解消 |
| #1684 IS_AUTOPILOT cwd-guard | B (worktree pilot 専任) | **W** | B 強化 + W で構造的解消 |
| #1687 twl mcp disconnect | (なし) | **X** (deploy/verify セット) | 新規 X で構造的解消 |
| #1703 phase-review.json cross-pollution | (なし) | **T** + **V** | 新規 T/V で構造的解消 |
| #973 RED merge silent rot | S (RED-only bypass 閉塞) | **U** | S 部分 Superseded + U で構造的解消 |

= 9 P0 bug 全てが新規 invariant T-X (5 件) でカバー、横断要因 F-1/F-2/F-3 にも対応。

---

## 関連 spec ファイル

- 新規 invariant T-X の具体実装: `step-verification.html` (Inv U) / `spawn-protocol.html` (Inv T/V、placeholder) / `gate-hook.html` (Inv W、placeholder) / `crash-failure-mode.html` (Inv G 強化)
- 既存 invariant 詳細: `plugins/twl/refs/ref-invariants.md` (本 spec で drift 訂正課題対応)

---

## audit 方法

- 既存 invariant 19 件: `ref-invariants.md` を本 session で Read 済 (verified)
- 新規 invariant T-X: 9 P0 bug 分析 (`failure-analysis.md`) の lesson から導出
- confidence: 既存 = verified (file read 済)、新規 = deduced (本 spec 設計から)
