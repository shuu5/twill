# deletion-inventory — placeholder

**status**: placeholder (本 session 未実装、次 session で着手予定)

> 本 file は `twill-plugin-rebuild` spec の placeholder。次 session で削除対象 60+ 件の詳細 inventory + 新規 helper 5 本の役割を実装する。draft-v1 §9 の内容を発展。

## 目的

新 spec で削除する既存 file (bash 5175 lines + workflow-* 13 個 + ADR Superseded 6 件 + checkpoint 系) と、新規追加する helper 5 本 (mailbox.sh / step.sh / phase-gate.sh / spawn-tmux.sh / admin-cycle.sh、合計 ~200 lines) の inventory を仕様化する。

## 想定 outline (次 session で実装)

1. **削除対象 (bash orchestration ~5000 lines)**
   - `chain-runner.sh` (1932) / `autopilot-orchestrator.sh` (1508) / `issue-lifecycle-orchestrator.sh` (879) / `autopilot-launch.sh` (548) / `auto-merge.sh` (308)
   - `spawn-controller.sh` / `cld-spawn` / `session-comm.sh` / `pseudo-pilot`
   - `mcp-watchdog.sh` / heartbeat-watcher / wave-progress-watchdog / pilot-fallback-monitor
   - `autopilot-*.sh` 群 (~20 本)
   - `merge-gate-*.sh` (10 本、step verification で代替)
   - `cld-observe-any.sh` / observer-* monitoring scripts

2. **削除対象 (chain SSoT 三重化 + checkpoint)**
   - `chain.py` CHAIN_STEPS (Python 側)
   - `chain-steps.sh` (computed mirror)
   - `chain` (slash command)
   - `twl check --deps-integrity` (SSoT 同期不要なので廃止)
   - `.autopilot/checkpoints/` / `.autopilot/issues/` / `.supervisor/events/`
   - `phase-review.json` (cross-pollution root cause)

3. **削除対象 (skill 24 → 15)**
   - `workflow-pr-cycle` (DEPRECATED 確定)
   - `workflow-*` 13 個 → worker-* に統合 or phase-* SKILL.md に inline
   - co-* 7 個 → phase-*/tool-* に rebrand

4. **削除対象 (twl MCP 7 hook → 1 hook)**
   - `twl_validate_merge` / `twl_validate_commit` / `twl_validate_status_transition` / `twl_validate_issue_create` / `twl_check_specialist x2` 削除
   - `twl_validate_deps` のみ保全 (deps.yaml syntax 確認)

5. **新規 helper 5 本 (~200 lines)**
   - `mailbox.sh` (~30 lines、file mailbox send/recv、flock atomic)
   - `step.sh` (~80 lines、step verification framework、4 phase lifecycle)
   - `phase-gate.sh` (~30 lines、PreToolUse hook handler、status check)
   - `spawn-tmux.sh` (~30 lines、tmux new-window wrapper、3 階層共通)
   - `admin-cycle.sh` (~30 lines、CronCreate handler、polling cycle)

6. **保全対象**
   - ADR 27 件 (詳細 `adr-fate-table.md`)
   - 不変条件 14 件 (詳細 `invariant-fate-table.md`)
   - refs 配下大半 (intervention-catalog / pitfalls-catalog / monitor-channel-catalog 等)
   - cli/twl/ の validate / status / config / mcp_server (極小化)
   - bats regression test 90+ (新規 5 件追加、削除なし)

## 参照

- `overview.html` §6 (構造的欠陥 3 種と不能化)
- `failure-analysis.md` (削除根拠の lesson)
- `adr-fate-table.md` (ADR fate)
- `invariant-fate-table.md` (新規 invariant T-X が削除対象を unjustify)
- 既存 draft `/tmp/twill-rebuild-design.html` §9 (原案、bash 5175 → 200 lines の比較 bar chart)
