# ADR-043: twill plugin radical rebuild — 3 階層 architecture + plugin 化 + experiment-verified spec

**Status**: Proposed (draft、2026-05-13)

**Supersedes (完全置換)**: ADR-020, ADR-022, ADR-034, ADR-039

**Supersedes (部分置換)**: ADR-003, ADR-021, ADR-023, ADR-024, ADR-025, ADR-029, ADR-038, ADR-041, ADR-042

**Strengthens (補強)**: ADR-006, ADR-008, ADR-010, ADR-014, ADR-017, ADR-026, ADR-027, ADR-028, ADR-035, ADR-040

**Inherits (保全継承)**: その他 22 件 ADR

**References**: `architecture/spec/twill-plugin-rebuild/` directory (本 spec 全体、24 file + draft-v1.html archive)

---

## Context

twill plugin は 2026-04〜2026-05 の運用で以下の構造的欠陥が顕在化:

1. **bash orchestration 巨大化**: scripts/ 116 file / 16,747 行 (実測 verified)、chain-runner.sh 1714 行 / autopilot-orchestrator.sh 1355 行等
2. **chain SSoT 三重化** (ADR-022 で正式定義): chain.py (905 行) + chain-steps.sh (98 行、computed) + deps.yaml.chains の同期破綻
3. **9 件 P0 bug 連発** (2026-05-12 verified): #1660 SKIP sanitize / #1662-1663 OBSERVER_PARALLEL_CHECK / #1673 cross-wave cleanup / #1674 orchestrator early-exit / #1684 IS_AUTOPILOT cwd-guard / #1687 twl mcp disconnect (5 回再発) / #1703 phase-review.json cross-pollution / #973 RED merge silent rot (5 ヶ月放置)
4. **upstream 仕様制約**: claude CLI `--skill` flag 不存在 (verified)、stdio MCP auto-reconnect 不在 (#43177 verified)、CronCreate durable=true bug (#40228 verified)

横断要因 (verified):
- **F-1**: 並列 Wave の設計が後付け (共通 state path、cleanup スコープ未更新)
- **F-2**: env var による機械的 enforcement の限界 (型なし、スコープなし、継承デフォルト on)
- **F-3**: deploy / verify 分離欠如 + upstream 仕様制約

## Decision

twill plugin を **radical rebuild** する。設計の核心:

### 1. 3 階層 architecture (admin / pilot / worker) + tool-*

- **L0 administrator** (1 個、user 代理、長命 main session): 旧 su-observer rebrand、CronCreate polling + Project Board status SSoT
- **L1 pilot (phase-*)**: 4 種 (phase-explore / phase-refine / phase-impl / phase-pr)、status 遷移 1 件専任、worker spawn + mail 集約
- **L2 worker (worker-*)**: 3-5 種 (worker-test-ready / worker-pr-fix / worker-pr-cycle 等)、worktree 内で step.sh 実行
- **tool-* 独立**: **3 件** (tool-architect / tool-project / tool-sandbox-runner)、status 遷移と無関係、user/admin 直接 invoke。第 4 弾 dig (2026-05-13) で旧 4 件 → 3 件構成確定:
  - **tool-utility 廃止**: 79 行 SKILL.md + 6 commands を tool-architect / tool-project / admin inline / tool-sandbox-runner に再分配
  - **tool-self-improve → tool-sandbox-runner rename**: scope 明確化 (sandbox × feature matrix + LLM 分析 + Idea Issue 起票)
  - **tool-architect 自律 verify 2 層**: SKILL.md MUST (LLM 4-state grep) + PostToolUse hook `verify-coverage.sh` (warn-only)
  - **軽量 PR cycle**: spec edit → PR → `worker-spec-review` 1 agent → fix loop 3 回上限 → user approve
  - **spec edit 所有権機械 enforce**: `pre-tool-use-spec-write-boundary.sh` で tool-architect / user 以外を deny
  - **sandbox catalog**: `plugins/twl/sandboxes/<name>/{sandbox.yaml, setup.sh, features.yaml}` + `_shared/problem-patterns.yaml`

### 2. twl Claude Code 公式 plugin 化 (長期安定)

- `plugins/twl/.claude-plugin/plugin.json` (manifest)
- skill namespace `/twl:*` 強制
- `plugins/twl/monitors/monitors.json` で Plugin Monitor 採用 (mcp-watchdog 廃止代替)
- `plugins/twl/hooks/hooks.json` で PreToolUse phase-gate
- `claude --plugin-dir plugins/twl` + `/reload-plugins` で local test
- (verified source: <https://code.claude.com/docs/en/plugins>)

### 3. file mailbox (Inv T)

- `.mailbox/<session-name>/inbox.jsonl` per-session、flock atomic write
- pyramid 集約: worker → pilot → admin (Inv I-4)
- JSON Lines format {from, to, ts, event, detail, heartbeat_ts}

### 4. step verification framework (Inv U)

- 4 phase lifecycle: pre-check → exec → post-verify → report
- post-verify で機械検証 (test 数増加 / RED→GREEN / src diff)
- self-report-only step は廃止 (chain-runner L1873-1884 framing 訂正)

### 5. chain SSoT 単一化 (案 3、step.sh)

- chain.py / chain-steps.sh / `twl check --deps-integrity` 全廃
- 1 step = 1 `steps/<name>.sh` file = 単一 SSoT
- `_verify_<name>()` 関数で post-verify rule を同 file 内に
- 詳細: ADR-044 で別途

### 6. PreToolUse hook + MCP shadow tier の階層防御 (Inv W)

- tier 1: `command` hook (粗フィルタ + fast path)
- tier 2: `mcp_tool` hook = `twl_phase_gate_check` (stateful 判定)
- deny > ask > allow、bypassPermissions でも貫通 (verified)

### 7. experiment hyperlink architecture (living document)

- 4-state verification status (inferred → deduced → verified → experiment-verified) を各 claim に明示
- EXP-001〜018 体系で sandbox 実機検証 (公式 docs verify を再現確認)
- spec を living document として穴を計画的に埋める

## Consequences

### 削減効果 (verified)

- bash orchestration + tool-utility ~7,368 行 → 新規 helper ~700 行 (第 4 弾 dig 由来 7 件 ~440 行追加、**~90% 削減**)
- chain SSoT 3 重 → 1 重 (deps.yaml + steps/*.sh)
- twl MCP tool 30+ → ~15 + 1 新規 (`twl_validate_project_setup`)
- skill 24 → **~11-13** (第 4 弾 dig で tool-utility 廃止により 1 件減)

### 9 P0 bug の構造的不能化

| Bug | 不能化機構 |
|---|---|
| #1660 / #1662 / #1663 / #1684 | PreToolUse hook (Inv W) でも env bypass 不可、Project Board status SSoT |
| #1673 | per-Worker worktree scope (Inv V) |
| #1674 | orchestrator 概念廃止、admin polling cycle で代替 |
| #1687 | Plugin Monitor (Inv X) で deploy/verify セット、自前 watchdog 廃止 |
| #1703 | per-Worker mailbox (Inv T/V)、共通 path 廃止 |
| #973 | step verification post-verify 機械化 (Inv U) |

### Migration (Strangler Fig 4 phase)

1. **Phase 1 PoC (Day 1-3)**: sandbox EXP 実行 (EXP-001〜031 計 31 件) → twl plugin 化 → 新 helper 5 本 + 第 4 弾 dig 由来 7 件 → Issue #1660 sanitize を新 architecture で再実装。verify points VP-1〜VP-16 (本 dig で VP-13〜VP-16 追加: tool-architect verify + tool-project Project write boundary + tool-sandbox-runner)
2. **Phase 2 dual-stack (Day 4-7)**: 残り phase / worker / **tool-* 3 件** 実装 (第 4 弾 dig)、`shuu5/twill-templates` 別 repo 作成、旧 chain freeze
3. **Phase 3 cutover (Day 8-11)**: 旧 bash ~7,000 行削除、in-flight Issue 全完遂
4. **Phase 4 cleanup (Day 12-14)**: docs 整合、bats regression 全 PASS、本 ADR を Accepted 化

### 既存 ADR 継承戦略

詳細: `architecture/spec/twill-plugin-rebuild/adr-fate-table.html`

Superseded chain の起票順序は同 file §「Superseded chain の起票順序 (実装計画)」参照。

## Verification

本 ADR の核心 claim は以下の EXP で実機検証する (詳細: spec の `experiment-index.html`):

- EXP-001〜003: PreToolUse hook schema (Inv W 構造的保証)
- EXP-004: CronCreate durable bug reproduce
- EXP-005: stdio MCP auto-reconnect 不在 reproduce
- EXP-006: file mailbox flock atomic (Inv T)
- EXP-007〜008: tier 1+2 hook parallel + bypassPermissions deny
- EXP-009: Plugin Monitor stdout notification
- EXP-010: twl plugin 化 + namespace 解決
- EXP-011〜013: step.sh framework + per-Worker scope (Inv U/V)
- EXP-014: bash 4.3+ nameref 動作 (CI image)
- EXP-015〜018: gh / tmux / fastmcp toolchain
- **EXP-019〜023 (第 4 弾 dig)**: GitHub Project 5 領域 × 4 手段 write boundary (status field option / kanban col order / label / view / filter)
- **EXP-024 (第 4 弾 dig、将来)**: twl MCP custom tool 価値調査
- **EXP-025〜026 (第 4 弾 dig)**: template apply + build / idempotent
- **EXP-027〜029 (第 4 弾 dig)**: tool-architect verify (verify-coverage.sh / spec-write-boundary / worker-spec-review fix loop 収束)
- **EXP-030〜031 (第 4 弾 dig)**: tool-sandbox-runner (twill-self sandbox 1 cycle / doobidoo 重複 check 精度)

Phase 1 PoC 着手前に EXP-001〜010 + EXP-027〜028 (本 dig 由来の bats 完結 EXP) を最低 PASS 必須。EXP-019〜023 は tool-project 実装前に PASS、EXP-030〜031 は最後 (sandbox-runner 実装後)。

## Supplement

本 ADR の **supplement** は `architecture/spec/twill-plugin-rebuild/` directory 全体 (25 file、第 4 弾 dig で 1 file 追加):

主要 file:
- `overview.html` — 全体図 + 新原則 9 条
- `failure-analysis.html` — 9 P0 bug 深掘り + 横断要因 F-1/F-2/F-3
- `adr-fate-table.html` — ADR 43 件 fate audit
- `invariant-fate-table.html` — A-X 24 件
- `tool-architecture.html` — tool-* **3 件**詳細 (第 4 弾 dig 反映、自律 verify 2 層 + 軽量 PR cycle + sandbox catalog)
- `sandbox-experiment.html` — EXP-id system 設計 + `plugins/twl/sandboxes/` catalog (第 4 弾 dig 追加)
- `experiment-index.html` — EXP-001〜031 (本 dig で 13 件追加: EXP-019〜031)
- `research-findings.html` — 公式 verify source 集約 (120 sources + 本 session 13 件 WebFetch)
- **`dig-report-tools-2026-05-13.md`** (第 4 弾 dig 独立 artifact、12 section / ~510 行、57 claim を 4-state status で分類)

## Status timeline

- 2026-05-13: Proposed (第 4 弾 dig 完了で tool-* 3 件構成確定、ADR-044 と同時起票準備、spec 反映完了)
- (予定) Phase 1 PoC 完遂後: Accepted

## Related

- ADR-044: chain SSoT 統一 (案 3 step.sh 詳細設計)
- Superseded chain: spec の adr-fate-table.html 参照
- research session: doobidoo hash `6fdf1d0b69a4d272111ec9fb34052914fab546c1bc6c61cbd4b006c48e4cc345`
- 本 session の doobidoo hash 累積: `3d10303e` (第 1 弾) / `4a6f90b9` (第 2 弾) / `ca37a5de` (第 3 弾) / **`a6d6b7c1`** (第 4 弾 dig) / (第 5 弾 spec 反映完了で追加保存予定)
