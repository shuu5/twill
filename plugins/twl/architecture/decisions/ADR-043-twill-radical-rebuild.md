# ADR-043: twill plugin radical rebuild — 10 role architecture + plugin 化 + registry.yaml 統合 SSoT + experiment-verified spec

**Status**: Proposed (draft、2026-05-13、第 5 弾 dig で 10 role + registry.yaml + 命名 policy 確定)

**Supersedes (完全置換)**: ADR-020, ADR-022, ADR-034, ADR-039

**Supersedes (部分置換)**: ADR-003, ADR-021, ADR-023, ADR-024, ADR-025, ADR-029, ADR-038, ADR-041, ADR-042

**Strengthens (補強)**: ADR-006, ADR-008, ADR-010, ADR-014, ADR-017, ADR-026, ADR-027, ADR-028, ADR-035, ADR-040

**Inherits (保全継承)**: その他 22 件 ADR

**References**: `architecture/spec/twill-plugin-rebuild/` directory (本 spec 全体、27 file + draft-v1.html archive、第 5 弾 dig で 2 file 追加: `dig-report-ssot-2026-05-13.md` + `registry-schema.html`)

---

## Context

twill plugin は 2026-04〜2026-05 の運用で以下の構造的欠陥が顕在化:

1. **bash orchestration 巨大化**: scripts/ 116 file / 16,747 行 (実測 verified)、chain-runner.sh 1714 行 / autopilot-orchestrator.sh 1355 行等
2. **chain SSoT 三重化** (ADR-022 で正式定義): chain.py (905 行) + chain-steps.sh (98 行、computed) + deps.yaml.chains の同期破綻
3. **9 件 P0 bug 連発** (2026-05-12 verified): #1660 SKIP sanitize / #1662-1663 OBSERVER_PARALLEL_CHECK / #1673 cross-wave cleanup / #1674 orchestrator early-exit / #1684 IS_AUTOPILOT cwd-guard / #1687 twl mcp disconnect (5 回再発) / #1703 phase-review.json cross-pollution / #973 RED merge silent rot (5 ヶ月放置)
4. **upstream 仕様制約**: claude CLI `--skill` flag 不存在 (verified)、stdio MCP auto-reconnect 不在 (#43177 verified)、CronCreate durable=true bug (#40228 verified)
5. **用語多重化** (第 5 弾 dig 2026-05-13 で発覚): pilot/phase/controller 5 重、worker 5 重、step 5 重、agent 4 重、tool 4 重、state/status 2 重、mail/event/message 3 重、events directory 1 重、制御系 4 語 (administrator/orchestrator/controller/supervisor) — 「1 entity = 1 name」違反の SSoT 多重化

横断要因 (verified):
- **F-1**: 並列 Wave の設計が後付け (共通 state path、cleanup スコープ未更新)
- **F-2**: env var による機械的 enforcement の限界 (型なし、スコープなし、継承デフォルト on)
- **F-3**: deploy / verify 分離欠如 + upstream 仕様制約
- **F-4** (第 5 弾 dig): 用語 SSoT の不在による drift (同 entity を別語で参照、role 名混乱、audit 不能)

## Decision

twill plugin を **radical rebuild** する。設計の核心:

### 1. 10 role architecture (第 5 弾 dig 確定、旧 3 階層 から拡張)

第 5 弾 dig (`architecture/spec/twill-plugin-rebuild/dig-report-ssot-2026-05-13.md` Round 1-10) で 10 role 体系に確定:

詳細 matrix (allowed-tools / can_spawn / 公式仕様根拠 / vocabulary entry を含む 8 column matrix) は `architecture/spec/twill-plugin-rebuild/registry-schema.html` §3 を参照。本 ADR では中核 6 column を sub-table として記載:

| # | role | prefix | location | description 有無 | 役割 (主要 can_spawn) |
|---|---|---|---|---|---|
| 1 | **administrator** | (singleton) | `skills/administrator/` | 有 | L0、長命 main session、Project Board status SSoT polling、phaser-* + tool-* を spawn |
| 2 | **phaser** | `phaser-` | `skills/phaser-*/` | 有 | L1、status 遷移 1:1 (旧 pilot/phase/controller 5 重を 1 語統一)、workflow-* を `Skill()` で / specialist-* を `Agent()` で spawn |
| 3 | **tool** | `tool-` | `skills/tool-*/` | 有 | admin/user session 内独立 skill、status 無関係 (公式 `Tool` とは大文字 + backtick で区別)、specialist-* を `Agent()` で spawn 可 |
| 4 | **workflow** | `workflow-` | `skills/workflow-*/` | 無 (`disable-model-invocation: true`) | phaser/tool から `Skill()` で呼ばれる sub-workflow、atomic-* を `Skill()` で順次呼ぶ launcher |
| 5 | **atomic** | `atomic-` | `skills/atomic-*/` | 無 (同上) | 最小実行単位、workflow から `Skill()` で呼ばれる、必要時のみ `Agent(specialist-*)` で spawn |
| 6 | **specialist** | `specialist-` | `agents/specialist-*.md` (公式 directory) | 有 (公式仕様必須) | `Agent` tool 経由 sub-agent、独立 context window、**subagent spawn 不可** (sub-agents docs verbatim verified) |
| 7 | **reference** | `ref-` | `refs/ref-*.md` | 概念外 | 不変条件 / prompt guide / pitfalls catalog 等の正典 doc |
| 8 | **script** | event-based | `scripts/hooks/<event>-*.sh` | 概念外 | hook handler bash (skill 呼び出し用 script = 0 目標) |
| 9 | **hook** | (registry entry) | `hooks/hooks.json` | 概念外 | Claude Code event handler config |
| 10 | **monitor** | (registry entry) | `monitors/monitors.json` | 概念外 | background process (stdout 各 line が session notification) |

**tool-* 独立** (第 4 弾 dig 確定): **3 件** (tool-architect / tool-project / tool-sandbox-runner)、user/admin 直接 invoke。
  - **tool-utility 廃止**: 79 行 SKILL.md + 6 commands を tool-architect / tool-project / admin inline / tool-sandbox-runner に再分配
  - **tool-self-improve → tool-sandbox-runner rename**: scope 明確化 (sandbox × feature matrix + LLM 分析 + Idea Issue 起票)
  - **tool-architect 自律 verify 2 層**: SKILL.md MUST (LLM 4-state grep) + PostToolUse hook `verify-coverage.sh` (warn-only)
  - **軽量 PR cycle**: spec edit → PR → `specialist-spec-review` 1 agent → fix loop 3 回上限 → user approve (第 5 弾 dig で `worker-spec-review` → `specialist-spec-review` rename)
  - **spec edit 所有権機械 enforce**: `pre-tool-use-spec-write-boundary.sh` で tool-architect / user 以外を deny
  - **sandbox catalog**: `plugins/twl/sandboxes/<name>/{sandbox.yaml, setup.sh, features.yaml}` + `_shared/problem-patterns.yaml`

### 2. twl Claude Code 公式 plugin 化 (長期安定)

- `plugins/twl/.claude-plugin/plugin.json` (manifest)
- skill namespace `/twl:*` 強制
- `plugins/twl/monitors/monitors.json` で Plugin Monitor 採用 (mcp-watchdog 廃止代替)
- `plugins/twl/hooks/hooks.json` で PreToolUse phase-gate
- `claude --plugin-dir plugins/twl` + `/reload-plugins` で local test
- (verified source: <https://code.claude.com/docs/en/plugins>)

### 3. file mailbox (Inv T) — 4 階層 entity (第 5 弾 dig 確定)

- `mailbox` (`.mailbox/<session-name>/`) — directory
- `inbox` (`.mailbox/<session-name>/inbox.jsonl`) — file
- `mail` — inbox.jsonl 1 行 entry (JSON Lines)
- `event` — mail.event field (e.g. `step-completed`)
- pyramid 集約: specialist → atomic → workflow → phaser → administrator (役割名で記述、旧 worker→pilot→admin から rename)
- JSON Lines format `{from, to, ts, event, detail, heartbeat_ts}`
- `.supervisor/events/` directory は完全廃止、mailbox 統一 (第 5 弾 dig Round 10)

### 4. Atomic skill verification (Inv U、旧 Step verification framework を rename)

- 4 phase lifecycle: pre-check → exec → post-verify → report
- atomic SKILL.md 本文に **inline 実装** (旧 `step.sh framework` 外部 bash 呼び出しを廃止)
- post-verify で機械検証 (test 数増加 / RED→GREEN / src diff)
- self-report-only は廃止 (chain-runner L1873-1884 framing 訂正)
- 詳細: `architecture/spec/twill-plugin-rebuild/atomic-verification.html` (旧 `step-verification.html` から rename)

### 5. registry.yaml 統合 SSoT (第 5 弾 dig 確定、案 4)

第 5 弾 dig で「案 3 step.sh 単一 SSoT」から「**案 4 registry.yaml 統合 SSoT**」に進化:

- **`plugins/twl/registry.yaml`** が all-in-one Authority SSoT (旧 `cli/twl/types.yaml` + `plugins/twl/deps.yaml` + `step.sh` 単一 SSoT を全廃合成)
- 5 section: `glossary` (vocabulary table) + `components` (全 file listing) + `chains` (workflow→atomic sequence + verify rule) + `hooks/monitors` (entry config) + `integrity_rules` (audit ルール)
- chain.py / chain-steps.sh / `twl check --deps-integrity` 全廃
- 1 atomic = 1 `skills/atomic-*/SKILL.md` (公式 skill 機構準拠、独立 bash framework 不要)
- 詳細: `architecture/spec/twill-plugin-rebuild/registry-schema.html` (新規) + `ssot-design.html` (全面書き直し)

### 6. PreToolUse hook + MCP shadow tier の階層防御 (Inv W)

- tier 1: `command` hook (粗フィルタ + fast path)
- tier 2: `mcp_tool` hook = `twl_phase_gate_check` (stateful 判定)
- deny > ask > allow、bypassPermissions でも貫通 (verified)

### 7. experiment hyperlink architecture (living document)

- 4-state verification status (inferred → deduced → verified → experiment-verified) を各 claim に明示
- EXP-001〜038 体系で sandbox 実機検証 (第 5 弾 dig で EXP-032〜038 の 7 件追加)
- spec を living document として穴を計画的に埋める

### 8. 命名 policy (第 5 弾 dig Round 7-10 確定)

- **「1 entity = 1 name」ルール**: vocabulary table (registry.yaml glossary section) を Authority SSoT、`twl audit --vocabulary` で機械検証
- **vocabulary entry 6 field schema**: `canonical` / `aliases` / `forbidden` / `context` / `description` / `examples`
- **公式 Claude Code 名衝突回避**: 公式名 (`Agent`, `Skill`, `Tool`) は大文字始まり + backtick、twl 内部 entity は小文字 + role-prefix
- **言語 policy**: vocabulary canonical は英語 hyphen-kebab (公式 skill name 制約 verified: lowercase letters + numbers + hyphens のみ、`_` 不可)、説明文日本語可、entity 参照は backtick + 英語 canonical
- **role 1 語化**: false positive audit リスク回避のため、複合 role 名 (pilot-phase 試案) ではなく 1 語 role 体系で uniform (phaser / administrator / tool / workflow / atomic / specialist / reference / script / hook / monitor)
- **migration stage entity 例外**: Strangler Fig `Phase 1 PoC` / `Phase 2 dual-stack` 等は migration-stage entity として vocabulary table に登録、backtick + 大文字で `phase` forbidden audit から除外

### 9. 隠れ重複 SSoT の系統的解消 (第 5 弾 dig Round 10 確定)

| 旧多重 | 新方針 | 旧 occurrence |
|---|---|---|
| `state` vs `status` | `state` 液化、`status` 統一、`status-transition` canonical | state 102 |
| `mail` / `event` / `message` | 4 階層 (`mailbox` > `inbox` > `mail` > `event`) で明示、`message` 廃止 | message 10 |
| `.supervisor/events/` | 完全廃止、mailbox 統一 | (directory) |
| 制御系 4 語 (`administrator` / `orchestrator` / `controller` / `supervisor`) | `administrator` 統一、他 3 語は spec から液化 (backtick 引用のみ) | 108 |
| `pilot` / `phase` / `phase-*` / `controller` / `pilot-phase` | `phaser` 1 語統一 | 934 |
| `worker` / `worker-*` | `workflow` (L2 skill) + `specialist` (agents/) 2 分割 | 537 |
| `step` (一般語) / `step.sh` / `step::run` / `Step 0` etc. | 一般語 step 液化、`atomic` canonical、`Step 0`/`Step 1` は公式 SKILL.md スタイルで backtick 保全 | 716 |

## Consequences

### 削減効果 (verified、第 5 弾 dig 反映)

- bash orchestration + tool-utility ~7,368 行 → 新規 helper ~700 行 (第 4 弾 dig 由来 7 件 ~440 行追加、**~90% 削減**)
- chain SSoT 3 重 → 1 重 (registry.yaml に統合、deps.yaml + types.yaml + step.sh 全廃)
- twl MCP tool 30+ → ~15 + 1 新規 (`twl_validate_project_setup`)
- skill 24 → **~11-13** (第 4 弾 dig で tool-utility 廃止 + 第 5 弾 dig で workflow + atomic 細分)
- 用語多重化解消: pilot/phase/controller 5 重 → 1 (phaser)、worker 5 重 → 2 (workflow + specialist)、step 5 重 → 1 (atomic)

### 9 P0 bug の構造的不能化

| Bug | 不能化機構 |
|---|---|
| #1660 / #1662 / #1663 / #1684 | PreToolUse hook (Inv W) でも env bypass 不可、Project Board status SSoT |
| #1673 | per-specialist worktree scope (Inv V) |
| #1674 | orchestrator 概念廃止、administrator polling cycle で代替 |
| #1687 | Plugin Monitor (Inv X) で deploy/verify セット、自前 watchdog 廃止 |
| #1703 | per-phaser mailbox (Inv T/V)、共通 path 廃止 |
| #973 | atomic skill 4-phase post-verify 機械化 (Inv U) |

### Migration (Strangler Fig 4 phase、`Phase 1`〜`Phase 4` は migration-stage entity)

1. **`Phase 1 PoC` (Day 1-3)**: sandbox EXP 実行 (EXP-001〜038 計 38 件) → twl plugin 化 → registry.yaml 新規作成 + glossary section seed (core 12 entity) → 新 helper 5 本 + 第 4 弾 dig 由来 7 件 + 第 5 弾 dig 由来 atomic skill 群 → Issue #1660 sanitize を新 architecture で再実装。verify points VP-1〜VP-20 (第 5 弾 dig で VP-17〜VP-20 追加: registry.yaml audit + atomic composition + vocabulary audit + 命名衝突検出)
2. **`Phase 2 dual-stack` (Day 4-7)**: 残り phaser / workflow / **tool-* 3 件** 実装、`shuu5/twill-templates` 別 repo 作成、旧 chain freeze、vocabulary table 拡張 (Phase 2: 隠れ重複 entity 追加)
3. **`Phase 3 cutover` (Day 8-11)**: 旧 bash ~7,000 行削除、in-flight Issue 全完遂、用語 rename 完遂 (~2000+ occurrence)
4. **`Phase 4 cleanup` (Day 12-14)**: docs 整合、bats regression 全 PASS、本 ADR を Accepted 化、命名 policy ADR (ADR-045) 起票

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
- EXP-011〜013: atomic skill 4-phase lifecycle + per-specialist scope (Inv U/V、第 5 弾 dig で旧 `step.sh framework` から rename + repurpose)
- EXP-014: bash 4.3+ nameref 動作 (CI image)
- EXP-015〜018: gh / tmux / fastmcp toolchain
- **EXP-019〜023 (第 4 弾 dig)**: GitHub Project 5 領域 × 4 手段 write boundary (status field option / kanban col order / label / view / filter)
- **EXP-024 (第 4 弾 dig、将来)**: twl MCP custom tool 価値調査
- **EXP-025〜026 (第 4 弾 dig)**: template apply + build / idempotent
- **EXP-027〜029 (第 4 弾 dig)**: tool-architect verify (verify-coverage.sh / spec-write-boundary / specialist-spec-review fix loop 収束)
- **EXP-030〜031 (第 4 弾 dig)**: tool-sandbox-runner (twill-self sandbox 1 cycle / doobidoo 重複 check 精度)
- **EXP-032 (第 5 弾 dig)**: registry.yaml audit (重複 concern 検出 + prefix↔role 整合 + forbidden 使用検出)
- **EXP-033 (第 5 弾 dig)**: atomic skill composition (workflow → atomic Skill() 順次呼び出し)
- **EXP-034 (第 5 弾 dig)**: registry.yaml ↔ 実 SKILL.md frontmatter 整合性
- **EXP-035 (第 5 弾 dig)**: `disable-model-invocation: true` で context budget 効果実測 (token 数 before/after)
- **EXP-036 (第 5 弾 dig)**: atomic から `Agent(specialist-*)` spawn (`allowed-tools: [Skill, Agent]` declare)
- **EXP-037 (第 5 弾 dig)**: doobidoo cross-machine MCP の Tailscale 経由安定性 (100.82.69.124:18765)
- **EXP-038 (第 5 弾 dig)**: `twl audit --vocabulary` の命名衝突検出 (`phaser` forbidden list (`pilot`/`phase`/`controller`) + 公式名 (`Agent`/`Skill`/`Tool`) false positive 抑制)

`Phase 1 PoC` 着手前に EXP-001〜010 + EXP-027〜028 + EXP-032〜034 (bats 完結 EXP) を最低 PASS 必須。EXP-019〜023 は tool-project 実装前に PASS、EXP-030〜031 + EXP-037 は最後 (sandbox-runner + Tailscale 連続稼働実装後)。

## Supplement

本 ADR の **supplement** は `architecture/spec/twill-plugin-rebuild/` directory 全体 (27 file、第 5 弾 dig で 2 file 追加):

主要 file:
- `overview.html` — 全体図 + 新原則 10 条 (第 5 弾 dig で「10 role + vocabulary」追加)
- `failure-analysis.html` — 9 P0 bug 深掘り + 横断要因 F-1/F-2/F-3 + F-4 (用語 SSoT 不在)
- `adr-fate-table.html` — ADR 43 件 fate audit
- `invariant-fate-table.html` — A-X 24 件
- **`registry-schema.html` (新規、第 5 弾 dig)** — registry.yaml schema + 10 role × concern matrix + vocabulary 6 field schema + Authority/Reference/Derived 階層図 (他 spec file の参照基盤)
- `glossary.html` — 10 role 正規定義 + vocabulary 6 field schema 説明 + Authority/Reference/Derived 用語 (第 5 弾 dig で全面更新)
- `ssot-design.html` — registry.yaml 統合 SSoT 設計 (第 5 弾 dig で全面書き直し、旧 step.sh 案 3 廃止)
- `tool-architecture.html` — tool-* **3 件**詳細 (第 4 弾 dig 反映、自律 verify 2 層 + 軽量 PR cycle + sandbox catalog) + phaser/workflow/specialist 用語適用 (第 5 弾 dig)
- `atomic-verification.html` (旧 `step-verification.html` から rename、第 5 弾 dig) — atomic skill 4-phase lifecycle specification
- `sandbox-experiment.html` — EXP-id system 設計 + `plugins/twl/sandboxes/` catalog (第 4 弾 dig 追加) + atomic composition + Agent spawn EXP sequence (第 5 弾 dig 追加)
- `experiment-index.html` — EXP-001〜038 (第 5 弾 dig で 7 件追加: EXP-032〜038)
- `research-findings.html` — 公式 verify source 集約 (120 sources + 本 session 累積 16 件 WebFetch)
- **`dig-report-tools-2026-05-13.md`** (第 4 弾 dig 独立 artifact、12 section / ~510 行、57 claim を 4-state status で分類)
- **`dig-report-ssot-2026-05-13.md`** (第 5 弾 dig 独立 artifact、13 section / ~921 行、10 round + 33+ question + vocabulary 6 field + 10 role + registry.yaml 統合 SSoT + 隠れ重複処理を包括)

## Status timeline

- 2026-05-12 (前 session): Proposed (初出、3 階層 + 4 tool-* + 案 3 step.sh)
- 2026-05-13 (前 session 第 4 弾 dig): tool-* 3 件構成確定 (tool-utility 廃止)、ADR-044 と同時起票準備、spec 反映完了
- **2026-05-13 (本 session 第 5 弾 dig)**: **10 role architecture 確定** (phaser 1 語統一)、**registry.yaml 統合 SSoT 確定** (案 3 step.sh → 案 4 registry.yaml)、**命名 policy 確定** (1 entity = 1 name + vocabulary 6 field schema)、**隠れ重複 SSoT 系統的解消** (state/mail/events/制御系 4 語)、spec 反映完了
- (予定) `Phase 1 PoC` 完遂後: Accepted

## Related

- ADR-044: chain SSoT 統一 (案 3 step.sh 詳細設計 → 案 4 registry.yaml 統合 SSoT に更新予定)
- ADR-045 (予定、第 5 弾 dig 由来): 命名 policy + vocabulary 6 field schema + 10 role 体系の formal ADR 化
- Superseded chain: spec の adr-fate-table.html 参照
- research session: doobidoo hash `6fdf1d0b69a4d272111ec9fb34052914fab546c1bc6c61cbd4b006c48e4cc345`
- 本 session の doobidoo hash 累積: `3d10303e` (第 1 弾) / `4a6f90b9` (第 2 弾) / `ca37a5de` (第 3 弾) / `a6d6b7c1` (第 4 弾 dig) / `09550ec2` (第 4 弾 spec 反映完了) / `5d6632b6` (第 5 弾 dig 第 1 部 Round 1-6) / **`dcc7511a`** (第 5 弾 dig 完成版 Round 1-10) / (第 5 弾 spec 反映完了で追加保存予定)
