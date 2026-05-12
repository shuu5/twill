---
name: twl:workflow-test-ready
description: |
  テスト生成と準備確認を実行する。workflow-setup の後に呼び出す。

  Use when user: says テスト準備/test-ready,
  or when called from workflow-setup chain.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-setup
tools: [Bash, Read, Skill]
maxTurns: 30
---

# テスト準備 Workflow

workflow-setup の後に呼び出す。`CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"` として使用。

## Worker TDD mental model（MUST READ）

この workflow は TDD の RED → GREEN フェーズを **本 workflow 内で完了** させる (ADR-039)。
Worker が PR 作成前に実装まで完了させる構造的 fix のため、test-scaffold 直後に PR を出してはならない。

- **RED**: AC から生成したテストが fail する状態は **正常**。これが実装の起点。
- **GREEN**: 同 workflow 内で `commands/green-impl.md` を実行し、impl_files を編集して全テストを PASS させる。
- **REFACTOR**: PASS 維持のまま品質を向上させる（optional、本 workflow の scope 外）。

**禁止事項（MUST NOT）**:
- テストの削除
- assertion を弱める（pass しやすいよう条件を緩める）
- 全テストが PASS している状態で実装を飛ばして進む
- **test-scaffold 直後 (RED 状態) で PR を作成する** — `pre-bash-pre-pr-gate.sh` hook で機械的に block される (ADR-039)

## chain 実行指示（MUST — 全ステップ順に実行。途中停止禁止）

### 前提: 前 workflow コンテキスト復元

```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
CONTEXT_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md"
[[ -n "$ISSUE_NUM" && -f "$CONTEXT_FILE" ]] && echo "=== 前 workflow コンテキスト ===" && cat "$CONTEXT_FILE"
```

### Step 0.5: cwd-guard（main ブランチ動作防止、Issue #1684 / invariant B + ADR-008）

```bash
bash "$CR" cwd-guard
```

main/master ブランチで動作している場合は exit 2 で abort（IS_AUTOPILOT=true + orchestrator early-exit 対策）。
source-touching step (test-scaffold) の直前に呼ぶことで fail-closed を実現する。
失敗（exit 2）は即座に停止し、Pilot に報告すること。

### Step 1: test-scaffold（AC-based）

`bash "$CR" llm-delegate "test-scaffold" "$ISSUE_NUM"` を実行し、`commands/test-scaffold.md` を Read → 実行。

AC-based test scaffold の入力:
- `${SNAPSHOT_DIR:-${CLAUDE_PLUGIN_ROOT:-.}/.dev-session/issue-${ISSUE_NUM:-unknown}}/01.5-ac-checklist.md`（不在は WARN のみ）
- Issue body の `## AC` / `## Acceptance Criteria` 節

出力: test ファイル（pytest/vitest/testthat）+ `ac-test-mapping.yaml`（AC 項目 → test path マッピング）

test-scaffold 完了後、test-first guard を実行:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tdd-red-guard.sh"
```
guard 失敗（テスト未生成 or 全 PASS）の場合は停止して報告。re-scaffold または実装のやり直しが必要。

`bash "$CR" llm-complete "test-scaffold" "$ISSUE_NUM"` を呼ぶ。

### Step 1.5: green-impl（GREEN 実装、RED test を PASS させる）

`bash "$CR" llm-delegate "green-impl" "$ISSUE_NUM"` を実行し、`commands/green-impl.md` を Read → 実行。

入力:
- `ac-test-mapping.yaml`（test-scaffold step が生成した RED test → impl_files マッピング）
- 各 AC の `impl_files` リスト（Glob/Grep で特定された実装対象パス）

green-impl の中で `agents/ac-scaffold-tests.md` を **`mode=green`** で呼び出し、impl_files 全件を編集/新規作成して RED test を GREEN に変える。

green-impl 完了後、GREEN guard を実行:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tdd-green-guard.sh"
```
guard 失敗（test fail or impl_files 不在）の場合は停止して報告。実装やり直しが必要。

`bash "$CR" llm-complete "green-impl" "$ISSUE_NUM"` を呼ぶ。

### Step 2: check 実行
`bash "$CR" check` → CRITICAL FAIL あれば報告して停止、なければ遷移へ。

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `test-scaffold green-impl check`

## 完了後の遷移（meta chain 定義から自動生成）

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num 2>/dev/null || echo "")
eval "$(bash "$CR" autopilot-detect)"
```

- IS_AUTOPILOT=true → context.md 書き出し（下記スニペット）→ 停止（orchestrator が `current_step=check` を terminal として検知し次 workflow を inject する）
- IS_AUTOPILOT=false → 「完了。次: /twl:workflow-pr-verify」と案内

**context.md 書き出しスニペット（停止直前）:**
```bash
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
  mkdir -p "${AUTOPILOT_DIR}/issues"
  cat > "${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md" <<EOF
# Workflow Context: Issue #${ISSUE_NUM}
workflow: test-ready

## completed_steps
- test-scaffold
- green-impl
- check

## pr_number


## test_results


## review_findings

EOF
fi
```
