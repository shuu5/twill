---
name: ref-chain-resume
description: co-autopilot が手動 PR 作成停止時の chain resume プロトコル
type: reference
---

# co-autopilot chain resume プロトコル

co-autopilot が手動 PR 作成などで停止した場合に chain を再開する手順。

## 診断手順

**Step 1: state file 確認**

```bash
# state file 存在確認
ISSUE=<N>
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
cat "${AUTOPILOT_DIR}/issues/issue-${ISSUE}.json" 2>/dev/null || echo "state file 不在"
```

確認項目:
- `status`: running / merge-ready / failed / done
- `current_step`: 最後に到達したステップ
- `pr`: PR 番号（null なら未リンク）
- `branch`: 実装ブランチ名

**Step 2: Pilot window 確認**

```bash
tmux list-windows -t <session-name> 2>/dev/null || tmux list-windows
# co-autopilot の Pilot window（例: issue-<N>）が存在するか確認
```

**Step 3: orchestrator プロセス確認**

```bash
pgrep -f autopilot-orchestrator.sh && echo "orchestrator 稼働中" || echo "orchestrator 停止"
```

---

## Case A: state file 不在

**症状**: `.autopilot/issues/issue-<N>.json` が存在しない。プロセスが完全に停止している。

**前提条件**: worktree（`feat/<N>-*`）が存在すること。

**手順**:

1. worktree の存在確認:
   ```bash
   git worktree list | grep "issue-${ISSUE}\|feat/${ISSUE}"
   ```

2. PR の存在確認:
   ```bash
   gh pr list --head "feat/${ISSUE}-" --json number,title,state 2>/dev/null
   ```

3. Pilot から spawn-controller で再起動（Pilot window で実行）:
   ```bash
   # .autopilot/plan.yaml の issue 一覧に N が含まれている場合
   spawn-controller.sh co-autopilot "Issue #${ISSUE} を再開する。worktree は存在する。"
   ```

   state file を手動で初期化してから再開する場合:
   ```bash
   python3 -m twl.autopilot.state write \
     --autopilot-dir "${AUTOPILOT_DIR:-.autopilot}" \
     --type issue --issue "${ISSUE}" --role pilot \
     --init --set "status=running" --set "branch=$(git branch --show-current)"
   spawn-controller.sh co-autopilot "Issue #${ISSUE} を再開する。"
   ```

---

## Case B: state file あり + chain 停止

**症状**: state file は存在するが chain が進まない。`current_step` が止まっている。

### B-1: PR が存在する場合（merge-ready に強制遷移）

PR が存在するが state に未リンク、または status が running/failed のまま停止:

```bash
# PR 番号を確認
PR_NUM=$(gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number -q '.[0].number')

# state に PR 番号を記録し merge-ready に強制遷移
python3 -m twl.autopilot.state write \
  --autopilot-dir "${AUTOPILOT_DIR:-.autopilot}" \
  --type issue --issue "${ISSUE}" --role pilot \
  --set "pr=${PR_NUM}" \
  --set "status=merge-ready" \
  --force-done \
  --override-reason "手動 PR 作成後 chain 停止のため強制遷移"
```

その後、merge-gate を実行（不変条件 C: `gh pr merge` 直接実行は禁止。必ず auto-merge.sh 経由）:
```bash
export ISSUE="${ISSUE}"
export PR_NUMBER="${PR_NUM}"
export BRANCH="$(python3 -m twl.autopilot.state read --type issue --issue "${ISSUE}" --field branch 2>/dev/null)"
python3 -m twl.autopilot.mergegate
```

### B-2: PR が存在しない場合（chain 再注入）

`current_step` が `ac-extract` や途中で停止しており PR が未作成:

```bash
# Worker window に次 workflow を inject（Pilot window から実行）
# inject する workflow は current_step に対応した次のステップ
# 例: current_step=ac-extract → workflow-test-ready を inject
WORKER_WINDOW="<worker-window-name>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-comm.sh" inject "$WORKER_WINDOW" \
  "/twl:workflow-test-ready #${ISSUE}"
```

---

## Case C: PR マージ済みだが state 未更新

**症状**: `gh pr view <N>` が `MERGED` を返すが state が done 以外。

**手順**:

1. マージ確認:
   ```bash
   gh pr view "${PR_NUM}" --json state -q '.state'
   # → MERGED であること
   ```

2. state を done に更新:
   ```bash
   python3 -m twl.autopilot.state write \
     --autopilot-dir "${AUTOPILOT_DIR:-.autopilot}" \
     --type issue --issue "${ISSUE}" --role pilot \
     --set "status=done" \
     --force-done \
     --override-reason "PR マージ済みだが state 未更新のため done に強制遷移"
   ```

3. Issue クローズ確認:
   ```bash
   gh issue view "${ISSUE}" --json state -q '.state'
   # CLOSED でなければ手動クローズ
   gh issue close "${ISSUE}"
   ```

---

## 関連リファレンス

- [compaction 復帰プロトコル](ref-compaction-recovery.md) — compaction 後の chain 再開手順
- [intervention-catalog.md](intervention-catalog.md) — observer 介入パターン（特に pattern 1: non_terminal_chain_end、pattern 2: Worker PR 未作成）
- [ref-invariants.md](ref-invariants.md) — 不変条件 C: マージは必ず auto-merge.sh 経由
