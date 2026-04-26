# Emergency Bypass マージ手順

co-autopilot 自体の障害時のみ手動パスを許可。bypass 使用時は retrospective で理由を記録。障害時は `commands/autopilot-phase-execute.md`・`commands/autopilot-poll.md`・`commands/autopilot-summary.md` を Read → 手動実行。

## マージ手順（MUST NOT 直接 gh pr merge）

Worker の `non_terminal_chain_end` 等で orchestrator が Emergency Bypass としてマージを実行する場合、**`gh pr merge` を直接呼んではならない**（squash ポリシーが適用されないため）。

必ず `mergegate merge --force` を使用すること:

```bash
python3 -m twl.autopilot.mergegate merge \
  --issue <ISSUE_NUM> \
  --pr <PR_NUMBER> \
  --branch <BRANCH> \
  --force
```

- `--force` がスキップするもの: `_check_running_guard()`（status=running 拒否）のみ
- `--force` でも維持されるもの: `_check_worktree_guard()`、`_check_worker_window_guard()`、`--squash` フラグ
- `gh pr merge --squash` が確実に呼ばれる（`--merge` ではない）
