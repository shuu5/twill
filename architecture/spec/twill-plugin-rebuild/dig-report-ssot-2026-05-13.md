# dig report — SSoT 体系 + 命名 policy + 10 role 統合 finalization (2026-05-13、第 5 弾 dig 完成版)

**目的**: twill plugin の SSoT 構造、命名規則、role 体系、隠れ重複を `dig` skill で対話的に詰めて 1 から再設計する。前 spec に内在した 5 矛盾 + 多数の用語衝突 (pilot/phase/controller 5 重 / worker/workflow 5 重 / step 5 重 / agent 4 重 / tool 4 重 / state/status 二重 / mail-event-message 3 重 etc.) を解消し、**1 entity = 1 name + registry.yaml 統合 SSoT + 命名衝突 audit 機械化** を達成する設計を確立。

**source**: 本 session で `dig` skill を **10 round × 平均 4 question = 33+ question** 実施。公式 docs 4 件再 WebFetch verify (plugins / skills / sub-agents / plugins-reference)。

**user の核心意図** (Round 1-10 通算):
- SSoT を「ただ呼ぶだけ」ではなく **階層構造 + グルーピング** で表現
- SSoT 間の **独立性を機械検証** (重複があれば SSoT ではない)
- 概念・用語の **共通基盤 + 1 entity = 1 name ルール**
- **1 file (registry.yaml) + 実 file の編集だけで構造維持** (AI による drift 防止)
- **公式仕様準拠** (skills / agents / commands / hooks / monitors 最新仕様、`_` separator 不可 verified)
- pilot/phase の重複から発覚した「隠れ SSoT 重複」を全件洗い出し
- EXP verify 必須

---

## 0. 結論

### 0.1 10 role 体系 (最終確定)

| # | role | prefix | location | description | 役割 |
|---|---|---|---|---|---|
| 1 | **administrator** | (singleton) | skills/ | 有 | L0、長命 main session、user 代理 |
| 2 | **phaser** | `phaser-` | skills/ | 有 | **L1**、別 session window controller、status 遷移 1:1 (旧 pilot/phase/controller → 1 語 `phaser` に統一) |
| 3 | **tool** | `tool-` | skills/ | 有 | admin/user session 内 skill、status 無関係 (公式 Tool とは backtick + 大文字で明示区別) |
| 4 | **workflow** | `workflow-` | skills/ | 無 (`disable-model-invocation: true`) | phaser/tool から `Skill()` 呼び出し、atomic 集合 |
| 5 | **atomic** | `atomic-` | skills/ | 無 (同上) | workflow から `Skill()` 呼び出し、最小実行単位 |
| 6 | **specialist** | `specialist-` | agents/ (公式 directory) | 有 (公式仕様) | `Agent()` tool 経由 sub-agent |
| 7 | **reference** | `ref-` | refs/ | 概念外 | 参照 doc |
| 8 | **script** | event-based (hook 用のみ) | scripts/hooks/ | 概念外 | hook handler bash (skill 呼び出し用 script = 0 目標) |
| 9 | **hook** | (registry entry) | hooks/hooks.json | 概念外 | event handler config |
| 10 | **monitor** | (registry entry) | monitors/monitors.json | 概念外 | background monitor config |

### 0.2 命名 policy (Round 7 確定)

- **「1 entity = 1 name」ルール**: vocabulary table (registry.yaml glossary) を Authority SSoT、`twl audit --vocabulary` で機械検証
- **公式 Claude Code 名衝突回避**: 公式名は **大文字始まり + backtick** (`Agent`, `Skill`, `Tool`), twl 内部名は **小文字 + role-prefix** (specialist, atomic-test-scaffold, tool-architect)
- **言語 policy**: vocabulary canonical は **英語 hyphen-kebab** (公式 skill name 仕様準拠: lowercase letters + numbers + hyphens のみ)、説明文は日本語可、entity 参照時は英語 canonical を backtick 引用
- **role 一語化**: false positive audit リスクを下げるため、複合 role 名 (pilot-phase 試案) ではなく **1 語 role 体系** で uniform (phaser / administrator / tool / workflow / atomic / specialist / reference / script / hook / monitor)

### 0.3 統合 SSoT

**`plugins/twl/registry.yaml`** が all-in-one Authority SSoT:
- **glossary section**: 10 role + 重要 entity の vocabulary table (canonical / aliases / forbidden / context / description / examples の 6 field)
- **components section**: 全 file の role / location / concern / depends / next を listing
- **chains section**: workflow → atomic の sequence + verify rule
- **hooks / monitors entry**: hooks.json / monitors.json の SSoT
- **integrity_rules section**: audit ルール定義

旧 `cli/twl/types.yaml` + `plugins/twl/deps.yaml` + 旧計画 `step.sh 単一 SSoT` は **registry.yaml に統合廃止**。

---

## 0.5 verify status と公式 source (本 dig 各 claim 検証)

### legend (4-state verification status)

| status | 意味 |
|---|---|
| **verified** | 公式 docs / 既存実装で確認済 |
| **deduced** | 型・docs・既存実装からの逆算 (公式直接記載なし) |
| **inferred** | 推測 (実機 EXP 実行で確定予定) |
| **experiment-verified** | sandbox 実機再現済 (将来) |

### 本 dig で WebFetch verified した公式 docs (2026-05-13 + 再 verify)

| docs URL | verify 内容 |
|---|---|
| [skills](https://code.claude.com/docs/en/skills) | SKILL.md frontmatter 全 field、**`disable-model-invocation: true` で description が context budget に乗らない** verbatim、**skill name は lowercase letters + numbers + hyphens のみ (max 64 chars、`_` 不可)** verbatim、commands/ は skills/ に merged |
| [sub-agents](https://code.claude.com/docs/en/sub-agents) | Subagent frontmatter (name+description 必須)、**subagent は subagent を spawn 不可** verbatim、**Agent tool が唯一の subagent spawn 経路** (Skill では subagent 呼べない)、plugin 由来 subagent は hooks/mcpServers/permissionMode 不可、`isolation: worktree` 可 |
| [plugins-reference](https://code.claude.com/docs/en/plugins-reference) | Plugin 6 component kind (skills/agents/hooks/MCP/LSP/monitors)、hook 27 lifecycle event、hook type 5 種 (command/http/mcp_tool/prompt/agent) |
| (前 dig 引用) [plugins](https://code.claude.com/docs/en/plugins) | `--plugin-dir` flag、skill namespace `/plugin:skill`、monitors/monitors.json |

### 主要 claim verify status

| claim | status | source / 備考 |
|---|---|---|
| L1 role = `phaser` (1 語、uniform 体系) | [deduced] | Round 9 で false positive audit リスク回避のため 1 語化選択、phase + -er suffix |
| skill name `_` 不可 | [verified] | skills docs verbatim "Lowercase letters, numbers, and hyphens only" |
| `disable-model-invocation: true` で context budget 外 | [verified] | skills docs verbatim 表「Description NOT in context」 |
| commands legacy → skills/ 統合 | [verified] | skills docs verbatim「Custom commands have been merged into skills」 |
| `Agent()` が subagent spawn の唯一経路 | [verified] | sub-agents docs verbatim |
| subagent は subagent spawn 不可 | [verified] | sub-agents docs verbatim「subagents cannot spawn other subagents」 |
| Plugin Monitor (mcp-watchdog 代替) | [verified] | plugins-reference + 第 3 弾 dig EXP-009 |
| Authority / Reference / Derived の 3 段階分類 | [deduced] | 設計選択合意、業界一般概念から逆算 |
| doobidoo cross-machine | [verified] | `claude mcp list` で「✓ Connected」http://100.82.69.124:18765/mcp (Tailscale 経由) |
| vocabulary audit (EXP-038) | [inferred → EXP-038] | Phase 1 PoC で実機検証 |
| registry.yaml schema (6 field vocabulary entry) | [deduced] | 設計合意 |
| state vs status: state 液化 | [deduced] | Round 10 確定 |
| mail-event-message 4 階層 (mailbox > inbox > mail > event) | [deduced] | Round 10 確定 |
| events directory 廃止 (.supervisor/events/) | [deduced] | Round 10 確定、第 4 弾 cleanup で既に rm 実施 |
| 制御系 4 語 → administrator 統一 | [deduced] | Round 10 確定 |

### 新規 EXP (本 dig 由来 7 件)

- EXP-032: registry.yaml audit (重複検出 + concern 整合性 + 命名衝突)
- EXP-033: atomic skill composition (workflow → atomic Skill() 順次呼び出し)
- EXP-034: registry.yaml ↔ 実 SKILL.md frontmatter 整合性
- EXP-035: `disable-model-invocation: true` で context budget 効果 measure
- EXP-036: specialist Agent() spawn from atomic (`allowed-tools: [Skill, Agent]` declare)
- EXP-037: doobidoo cross-machine MCP の Tailscale 経由安定性
- **EXP-038**: `twl audit --vocabulary` の命名衝突検出 (`phaser` 単独語 + forbidden list + 公式名衝突)

---

## 1. dig 履歴 (10 round 全件 transparency)

### Round 1 (4 question) — SSoT 用語体系 + 重複検出 + 用語統一 + 曖昧位置
1. SSoT 用語 → **Authority / Reference / Derived**
2. 重複検出 → **registry.yaml の unique + concern declare + audit**
3. types.py/deps.yaml の用語不整合 → ユーザー指摘「atomic/specialist/compose は残す、worker- は本来 workflow-」
4. doobidoo 位置 → ユーザー訂正「cross-machine 可能」

### Round 2 (4 question) — L2 命名 + types.yaml 統合 + step vs chain + doobidoo
5. L2 prefix → **workflow-***
6. types.yaml → **2 dimension 拒否、1 dimension 統合 + 名前修正**
7. step vs chain → ユーザー「**deps.yaml と step.sh を 1 file 統合**、公式仕様準拠」
8. doobidoo → **Knowledge Authority SSoT**

### Round 3 (4 question) — 統合 file name + role 体系 + step 実装 + 重複検出
9. 統合 SSoT file → **`plugins/twl/registry.yaml`** 新規
10. role 体系 → 9 role (composite 含む)
11. step 実装 → Round 4 で明確化
12. 重複検出 → registry.yaml で機械化

### Round 4 (1 question 再質問) — step 実装の明確化
13. step 実装 → **composition (atomic skill 化)**

### Round 5 (4 question) — commands 統合 + role 数 + script 最小化 + description 区分
14. commands → skills/ 統合、`disable-model-invocation: true` + description 省略
15. role 数 → ユーザー迷い「11 role 推奨」
16. script 最小化 → skill 呼び出し用 = 0、hook 用例外
17. description 有 → administrator + pilot + tool + specialist

### Round 6 (2 question) — composite 扱い + specialist rename
18-19. composite → **廃止 + atomic 統合**、10 role 確定
20. specialist rename → **全 file role-prefix rename**

### Round 7 (4 question) — 命名 policy
21. vocabulary SSoT → **registry.yaml glossary 統合**
22. 命名衝突検出 → **`twl audit --vocabulary`**
23. 公式名衝突 → **大文字+backtick (公式) vs 小文字+role-prefix (twl)**
24. 言語 policy → **canonical 英語 / 説明文日本語可**

### Round 8 (4 question) — L1 role 名 + 他 role 検証 + vocabulary schema + seed
25. L1 role → pilot-phase 試案 → Round 9 で再検討 (1 語化推奨)
26. 他 role 検証 → **tool/agent/step 3 重を並行 dig**
27. vocabulary entry schema → **6 field (canonical/aliases/forbidden/context/description/examples)**
28. vocabulary seed → **core entity 12 件**

### Round 9 (4 question) — L1 role 1 語化 + 3 重複処理
29. L1 role → **`phaser` (1 語、phase+er)**
30. tool 三重 → **tool-* keep + vocabulary 明示区別**
31. agent 四重 → **agents/ directory + specialist role + vocabulary 明示区別**
32. step 五重 → **step 液化、atomic 統一、lifecycle 別 entity**

### Round 10 (4 question) — 隠れ重複処理
33. state vs status → **state 液化、status 統一、status-transition canonical**
34. mail/event/message → **mailbox > inbox > mail > event の 4 階層**
35. events directory → **完全廃止、mailbox 統一**
36. 制御系 4 語 → **administrator 統一、他 3 語液化**

---

## 2. 命名 policy (Round 7 詳細)

### 2.1 「1 entity = 1 name」ルール

- 各 entity (administrator / phaser / tool / workflow / atomic / specialist / reference / script / hook / monitor + non-role entity: status / sandbox / EXP / mailbox / inbox / mail / event / lesson) は **1 つの canonical name** を持つ
- vocabulary table (registry.yaml glossary) に canonical + aliases (許容) + forbidden (禁止) を listing
- spec / code / docs で同一 entity を指す時は canonical を使う
- 公式 Claude Code 名と衝突する entity は backtick + 大文字始まりで明示分離

### 2.2 vocabulary entry の 6 field schema

```yaml
entity:
  canonical: phaser                              # 正規名 (英語 hyphen-kebab)
  aliases: []                                    # 許容同義語 (規約違反ではない)
  forbidden: [pilot, phase, controller]          # 禁止同義語 (audit で detect、書き換え要求)
  context: L1 role                               # どの文脈で使う entity か
  description: |                                  # 自由記述、日本語可
    別 session window controller、administrator が
    Project Board status に応じて spawn する。
    各 phaser は 1 つの status 遷移 (status-transition) を担当。
  examples:                                       # 実例
    - phaser-explore
    - phaser-refine
    - phaser-impl
    - phaser-pr
```

### 2.3 公式 Claude Code 名衝突回避ルール

| 公式名 | spec での書き方 | twl 内部 entity の対応物 |
|---|---|---|
| `Agent` (tool) | 大文字始まり + backtick | specialist (role)、agents/ (directory) |
| `Skill` (tool) | 大文字始まり + backtick | (twl 側 entity なし、機構名として `Skill` で OK) |
| `Tool` (abstract) | 大文字始まり + backtick | tool (role、小文字 + tool-* prefix で識別) |
| `Bash`, `Edit`, `Read`, `Write` etc. | 大文字始まり + backtick | (twl 側 entity なし) |
| `Plan` (agent type) | 大文字始まり + backtick | (twl 側 entity なし) |
| `Explore` (agent type) | 大文字始まり + backtick | (twl 側 entity なし) |

### 2.4 言語 policy

- **canonical (英語 hyphen-kebab)**: 公式 skill name 制約 verified「lowercase letters, numbers, and hyphens only」、`_` 不可
- **説明文**: 日本語可、ただし entity 参照時は英語 canonical を backtick 引用 (例: 「`invariant` (不変条件) は ...」)
- **既存日本語表記**: 「不変条件」「遷移」等は spec 内日本語説明としては OK だが、registry.yaml の canonical は `invariant` / `status-transition`

### 2.5 命名衝突 audit (`twl audit --vocabulary`)

新規 audit section (audit_collect の section 11 として追加):

```python
def audit_vocabulary(registry_yaml, spec_dir, code_dir) -> list[dict]:
    glossary = registry_yaml['glossary']
    items = []
    for entity_name, entry in glossary.items():
        forbidden = entry.get('forbidden', [])
        for forbidden_word in forbidden:
            # spec/*.html、cli/twl/**/*.py、plugins/twl/**/*.sh、*.md を grep
            for file in glob_files():
                for line, content in enumerate(file):
                    # word boundary 厳密 (正規表現 \b で囲む)
                    if matches_word_boundary(content, forbidden_word):
                        # ただし context (公式名 backtick 引用、説明用 etc.) は exclude
                        if not is_excluded_context(content, forbidden_word):
                            items.append({
                                "severity": "warning",
                                "section": "vocabulary",
                                "component": f"{file}:{line}",
                                "message": f"forbidden '{forbidden_word}' for entity '{entity_name}', canonical is '{entry['canonical']}'"
                            })
    return items
```

---

## 3. 各 role の詳細 (Round 9 ベース、phaser に修正)

### 3.1 administrator (singleton)
- **location**: `plugins/twl/skills/administrator/SKILL.md`
- **prefix**: なし
- **description**: 有 (user 直接 invoke 想定、AI auto-invoke も可)
- **役割**: L0、長命 main session、Project Board status SSoT を polling、phaser 群 + 一部 tool を spawn、phaser mail のみ受信 (pyramid 集約)
- **allowed-tools**: 全

### 3.2 phaser (phaser-explore / phaser-refine / phaser-impl / phaser-pr)
- **location**: `plugins/twl/skills/phaser-*/SKILL.md`
- **prefix**: `phaser-`
- **description**: 有 (administrator が AI 判断で select)
- **役割**: L1、別 session window controller、status 遷移 1:1 (Idea→Explored / Explored→Refined / Refined→Implementing / Implementing→PR Reviewed)、workflow を Skill() で順次呼ぶ
- **allowed-tools**: `[Skill, Bash, Read, mcp__twl__*]`、必要なら `Agent` 追加
- **rename source**: 旧 pilot / phase / phase-* / controller (1 語化、Round 9 確定)

### 3.3 tool (tool-architect / tool-project / tool-sandbox-runner)
- **location**: `plugins/twl/skills/tool-*/SKILL.md`
- **prefix**: `tool-`
- **description**: 有 (user / admin が直接 invoke)
- **役割**: status と無関係、独立 invoke、admin/user session 内で動作 (tool-sandbox-runner のみ別 sandbox 環境 spawn)
- **公式 `Tool` との区別**: spec 内で `Tool` (公式) は大文字+backtick、tool (twl role) は小文字+tool-* prefix
- **allowed-tools**: 各 tool で異なる

### 3.4 workflow (workflow-test-ready / workflow-pr-verify / etc.)
- **location**: `plugins/twl/skills/workflow-*/SKILL.md`
- **prefix**: `workflow-`
- **frontmatter**: `disable-model-invocation: true`、description 省略
- **役割**: phaser/tool から `Skill()` 呼び出し、atomic を順次呼ぶ launcher
- **allowed-tools**: `[Skill, Bash]`、必要なら `Agent`

### 3.5 atomic (atomic-test-scaffold / atomic-green-impl / etc.)
- **location**: `plugins/twl/skills/atomic-*/SKILL.md`
- **prefix**: `atomic-`
- **frontmatter**: `disable-model-invocation: true`、description 省略
- **役割**: 最小実行単位、workflow から `Skill()` 呼び出し、内部で必要なら `Agent(specialist-*)` で specialist spawn
- **allowed-tools**: `[Bash, Read, Write, Edit, Skill, Agent]`
- **lifecycle**: atomic SKILL.md 本文に 4-phase (pre-check → exec → post-verify → report) を inline 記述

### 3.6 specialist (specialist-code-reviewer / specialist-architecture / etc.)
- **location**: `plugins/twl/agents/specialist-*.md` (公式 `agents/` directory)
- **prefix**: `specialist-` (旧 worker-* 18 件を rename)
- **description**: 有 (公式仕様 必須)
- **役割**: `Agent` tool 経由で spawn される subagent、独立 context window、subagent は subagent spawn 不可
- **frontmatter**: 公式仕様準拠 (name/description/tools/model/effort/maxTurns/skills/isolation/color)

### 3.7 reference (ref-invariants / ref-prompt-guide / etc.)
- **location**: `plugins/twl/refs/ref-*.md`
- **prefix**: `ref-`
- **description**: 概念外
- **役割**: 不変条件 / prompt guide / pitfalls catalog 等の正典 doc

### 3.8 script (hook 用のみ)
- **location**: `plugins/twl/scripts/hooks/<event>-*.sh`
- **prefix**: event-based (`pre-tool-use-` / `post-tool-use-` / `pre-compact-` / etc.)
- **description**: 概念外
- **役割**: hook handler (公式 `command` type の bash 実装)
- **数**: 最小化目標 = 「skill 呼び出し用 script = 0」、hook 用のみ例外

### 3.9 hook (registry.yaml entry + hooks.json)
- **registry.yaml**: role: hook entry で event + matcher + handler を declare
- **role**: Claude Code lifecycle event handler

### 3.10 monitor (registry.yaml entry + monitors.json)
- **registry.yaml**: role: monitor entry
- **役割**: background process、stdout 各 line が Claude session に notification

---

## 4. vocabulary table (core 12 entity の seed)

```yaml
# plugins/twl/registry.yaml の glossary section (Phase 1 PoC seed)
glossary:
  # === 10 role ===
  administrator:
    canonical: administrator
    aliases: []
    forbidden: [orchestrator, controller, supervisor, su-observer]
    context: L0 role
    description: 長命 main session、user 代理、Project Board status SSoT を polling
    examples: [administrator]

  phaser:
    canonical: phaser
    aliases: []
    forbidden: [pilot, phase, controller, pilot-phase]  # 注: 「Phase 1 PoC」のような Strangler Fig は context で exclude
    context: L1 role
    description: |
      別 session window で動作する controller。
      administrator が Project Board status に応じて 1 phaser を spawn。
      各 phaser は 1 つの status 遷移 (`status-transition`) を担当。
    examples: [phaser-explore, phaser-refine, phaser-impl, phaser-pr]

  tool:
    canonical: tool
    aliases: []
    forbidden: []   # 公式 `Tool` は大文字+backtick で別 entity (公式名衝突 policy 適用)
    context: independent role
    description: |
      admin/user session 内で動作する独立 skill。status 遷移と無関係。
      公式 `Tool` (Bash/Edit 等) とは小文字 + tool-* prefix で識別。
    examples: [tool-architect, tool-project, tool-sandbox-runner]

  workflow:
    canonical: workflow
    aliases: []
    forbidden: [worker]
    context: L2 role (phaser から spawn)
    description: phaser / tool から Skill() で呼ばれる sub-workflow、atomic を順次呼ぶ launcher
    examples: [workflow-test-ready, workflow-pr-verify, workflow-pr-merge]

  atomic:
    canonical: atomic
    aliases: []
    forbidden: [step, composite]
    context: minimum unit (workflow から呼ばれる)
    description: |
      最小実行単位の skill。workflow から `Skill()` で呼ばれる。
      内部で必要なら `Agent(specialist-*)` で specialist spawn。
      4-phase lifecycle (pre-check / exec / post-verify / report) を内部実装。
    examples: [atomic-test-scaffold, atomic-green-impl, atomic-check]

  specialist:
    canonical: specialist
    aliases: []
    forbidden: [worker]
    context: subagent (agents/ directory)
    description: |
      `Agent` tool 経由で spawn される sub-agent。独立 context window。
      公式 `agents/` directory に配置 (公式仕様、変更不可)。
    examples: [specialist-code-reviewer, specialist-architecture, specialist-prompt-reviewer]

  reference:
    canonical: reference
    aliases: [ref]
    forbidden: []
    context: documentation
    description: 不変条件 / prompt guide / pitfalls catalog 等の正典 doc
    examples: [ref-invariants, ref-prompt-guide, ref-pitfalls-catalog]

  script:
    canonical: script
    aliases: []
    forbidden: []
    context: hook handler bash (hook 用のみ、skill 呼び出し用は 0)
    description: 公式 `command` type の hook 実装 bash file
    examples: [pre-tool-use-worktree-boundary, pre-compact-checkpoint]

  hook:
    canonical: hook
    aliases: []
    forbidden: []
    context: Claude Code event handler (hooks.json entry)
    description: 公式 hook lifecycle event の handler config
    examples: [hook-spec-write-boundary, hook-pre-compact]

  monitor:
    canonical: monitor
    aliases: []
    forbidden: []
    context: background process (monitors.json entry)
    description: Plugin Monitor (stdout 各 line が session notification)
    examples: [monitor-twl-mcp-health, monitor-budget-watcher]

  # === non-role 重要 entity ===
  status:
    canonical: status
    aliases: []
    forbidden: [state]
    context: Project Board status (Issue lifecycle)
    description: GitHub Project Board の Status field、6-stage (Idea/Explored/Refined/Implementing/PR Reviewed/Merged)
    examples: [Refined, Implementing, "PR Reviewed"]

  status-transition:
    canonical: status-transition
    aliases: [transition]
    forbidden: [遷移, phase as transition]
    context: 1 status から次 status への遷移 event
    description: phaser が担当する 1 つの status-transition
    examples: ["Refined → Implementing", "Implementing → PR Reviewed"]

  mailbox:
    canonical: mailbox
    aliases: []
    forbidden: [events, .supervisor/events/]
    context: file mailbox (.mailbox/<session>/)
    description: per-session file mailbox directory、flock atomic write (Inv T)
    examples: [".mailbox/administrator/", ".mailbox/phaser-impl-1660/"]

  inbox:
    canonical: inbox
    aliases: []
    forbidden: []
    context: mailbox 内の JSON Lines file
    description: mailbox directory 内の inbox.jsonl file
    examples: [".mailbox/administrator/inbox.jsonl"]

  mail:
    canonical: mail
    aliases: []
    forbidden: [message]
    context: inbox.jsonl の 1 entry (JSON Lines 1 行)
    description: |
      JSON Lines 1 行の mailbox entry。
      schema: {from, to, ts, event, detail, heartbeat_ts}
    examples: ['{"from":"phaser-impl","event":"step-completed","detail":{...}}']

  event:
    canonical: event
    aliases: []
    forbidden: []
    context: mail の event field
    description: mail JSON の event field (e.g. "step-completed")
    examples: [step-started, step-completed, step-postverify-failed, phase-completed]

  # === 4 階層 (Round 10 確定) ===
  # mailbox > inbox > mail > event の階層を vocabulary table に明示

  sandbox:
    canonical: sandbox
    aliases: []
    forbidden: []
    context: tool-sandbox-runner が実行する isolated 環境
    description: |
      plugins/twl/sandboxes/<name>/{sandbox.yaml, setup.sh, features.yaml} で定義される
      isolated 環境。twill-self (test-target/main orphan branch) や ts-nextjs-hono-mono
      等の sandbox catalog から選択。
    examples: [twill-self, ts-nextjs-hono-mono]

  EXP:
    canonical: EXP
    aliases: []
    forbidden: [experiment as singular id]
    context: sandbox experiment id (EXP-NNN format)
    description: experiment-index.html で listing される実機検証 experiment
    examples: [EXP-001, EXP-027, EXP-038]

  lesson:
    canonical: lesson
    aliases: []
    forbidden: []
    context: cross-session knowledge (doobidoo に保存)
    description: |
      session を越えて再利用される経験的知見。doobidoo Knowledge Authority SSoT
      (cross-machine HTTP MCP) に memory_store。tool-sandbox-runner が重複 check 後
      Idea Issue 起票 (severity=critical のみ)。
    examples: ["budget 表示 5h:N%(Xm) format 誤読", "tmux -C 破壊禁止"]
```

---

## 5. SSoT 階層構造 (Authority / Reference / Derived)

### 5.1 Authority SSoT (原典、人または合意が author)

| concern | Authority SSoT | 場所 |
|---|---|---|
| 設計仕様 | architecture spec | `architecture/spec/twill-plugin-rebuild/` (26 file) |
| 正典 ADR | ADR-043 等 | `plugins/twl/architecture/decisions/` |
| **component 構成 + vocabulary + chain + integrity rules** | **registry.yaml (新規)** | **`plugins/twl/registry.yaml`** |
| 不変条件 (invariant) | ref-invariants.md | `plugins/twl/refs/ref-invariants.md` |
| Issue lifecycle status | Project Board | external (twill-ecosystem) |
| **lesson** (cross-session knowledge) | **doobidoo MCP** | `http://100.82.69.124:18765/mcp` (cross-machine) |
| 各 SKILL.md / agent.md 本体 | 実 file の frontmatter + body | `skills/*/SKILL.md` + `agents/specialist-*.md` |

### 5.2 Reference SSoT (Authority から参照される正典)

| concern | Reference SSoT | Authority |
|---|---|---|
| EXP 結果集約 | experiment-index.html | 各 EXP-NNN.sh + 実行結果 .json |
| pitfalls catalog | ref-pitfalls-catalog.md | incident logs + lesson (doobidoo) |
| intervention catalog | ref-intervention-catalog.md | incident response (doobidoo) |
| monitor channel catalog | ref-monitor-channel-catalog.md | monitor 設計 (registry.yaml) |

### 5.3 Derived (自動生成、原典から派生)

| concern | Derived | Authority | drift 検出 |
|---|---|---|---|
| types.py `_FALLBACK_TOKEN_THRESHOLDS` | registry.yaml から生成 | registry.yaml | `twl audit` diff |
| README / CLAUDE.md component listing | registry.yaml から生成 | registry.yaml | `twl update-readme` |
| chain-steps.sh (旧、廃止) | chain.py から computed mirror | (廃止) | — |

### 5.4 階層関係図

```
[user / 設計者]
    │ author
    ▼
[architecture spec]  (本 dig 結果 = spec の supplement)
    │ supplement of
    ▼
[ADR-043 正典 md]  (実 SSoT 内 architecture spec が link)
    │ describes
    ▼
[Authority SSoT] ────────────────┬──────────────┬──────────────┐
    ├─ registry.yaml             │              │              │
    │   ├─ glossary (vocabulary) │              │              │
    │   ├─ components (listing)  │              │              │
    │   ├─ chains (workflow→atomic) │           │              │
    │   ├─ hooks (entry)         │              │              │
    │   ├─ monitors (entry)      │              │              │
    │   └─ integrity_rules       │              │              │
    ├─ ref-invariants.md         │              │              │
    ├─ Project Board (status)    │              │              │
    ├─ doobidoo (lesson)         │              │              │
    └─ 各実 file (SKILL.md / agent.md) ◀── refers via role/path ──┘

[Reference SSoT]
    ├─ experiment-index.html ◀── derived from EXP results
    └─ ref-*.md catalogs

[Derived (auto-generated)]
    ├─ types.py fallback ◀── from registry.yaml
    └─ README listing ◀── from registry.yaml
```

---

## 6. registry.yaml 完全 schema 案

```yaml
# plugins/twl/registry.yaml
# twill plugin の Authority SSoT
# version: 4.0 (旧 deps.yaml v3.0 + types.yaml + step 定義 + glossary を統合)

version: "4.0"
plugin: twl

# §1. glossary (vocabulary table、core 12 entity + 10 role + 重要 entity)
glossary:
  # ...上記 §4 参照

# §2. components (全 file の listing)
components:
  - name: administrator
    role: administrator
    file: skills/administrator/SKILL.md
    concern: top-level orchestration
    ssot_excludes: [status-transition, atomic-execution]

  - name: phaser-impl
    role: phaser
    file: skills/phaser-impl/SKILL.md
    concern: status-transition (Refined → Implementing)
    depends_on_status: Refined
    next_status: Implementing
    can_spawn: [workflow-test-ready, workflow-pr-verify, specialist-*]

  - name: tool-architect
    role: tool
    file: skills/tool-architect/SKILL.md
    concern: spec-editing
    can_spawn: [specialist-spec-review]

  - name: workflow-test-ready
    role: workflow
    file: skills/workflow-test-ready/SKILL.md
    concern: test scaffold sequence
    sequence: [atomic-test-scaffold, atomic-green-impl, atomic-check]

  - name: atomic-test-scaffold
    role: atomic
    file: skills/atomic-test-scaffold/SKILL.md
    concern: RED test 生成
    verify_rule: |
      bats_count_increased && red_test_failing && src_diff == 0
    can_spawn: []   # 通常 specialist 不要

  - name: specialist-code-reviewer
    role: specialist
    file: agents/specialist-code-reviewer.md
    concern: code quality review

  - name: ref-invariants
    role: reference
    file: refs/ref-invariants.md
    concern: invariant SSoT (A-X 24 件)

  - name: pre-tool-use-spec-write-boundary
    role: script
    file: scripts/hooks/pre-tool-use-spec-write-boundary.sh
    concern: spec edit boundary enforce
    used_by_hook: hook-spec-write-boundary

  - name: hook-spec-write-boundary
    role: hook
    event: PreToolUse
    matcher: Edit|Write
    handler_type: command
    handler: scripts/hooks/pre-tool-use-spec-write-boundary.sh
    concern: spec edit authority

  - name: monitor-twl-mcp-health
    role: monitor
    command: tail -F .mcp-health.log
    description: twl MCP server health log
    concern: MCP health observability

# §3. chains (workflow → atomic sequence、verify rule 集約)
chains:
  test-ready:
    workflow: workflow-test-ready
    steps:
      - name: atomic-test-scaffold
        verify: bats_count_increased && red_test_failing && src_diff == 0
      - name: atomic-green-impl
        verify: red_to_green_transition && green_test_passing
      - name: atomic-check
        verify: all_tests_pass && lint_pass
    next_workflow: workflow-pr-verify

# §4. integrity_rules (audit 用)
integrity_rules:
  - id: no_duplicate_concern
    description: 同じ concern を複数 role で保有してはならない
    severity: critical

  - id: ssot_authority_unique
    description: Authority SSoT は concern ごとに 1 つのみ
    severity: critical

  - id: derived_drift_check
    description: types.py fallback が registry.yaml から drift していないか
    severity: warning

  - id: prefix_role_match
    description: file prefix と role が一致 (phaser-* file は role phaser)
    severity: critical

  - id: vocabulary_forbidden_use
    description: forbidden 単語の使用 (audit --vocabulary section で検出)
    severity: warning   # 文脈で false positive あるため warning

  - id: official_name_collision
    description: 公式 Claude Code 名 (Agent/Skill/Tool 等) を backtick なしで twl 内部 entity として使用
    severity: warning

  - id: description_required_consistency
    description: |
      role が administrator/phaser/tool/specialist のみ description あり、
      他 role は disable-model-invocation: true + description 省略
    severity: warning
```

---

## 7. 隠れ重複処理 (Round 10 詳細)

### 7.1 state vs status

| 旧用法 | 新方針 |
|---|---|
| `state` (102 occurrence) | spec から液化、status に統一 |
| `status` (Project Board) | canonical 維持 |
| `transition` (4) / `遷移` (50) | canonical = `status-transition` (英語) |
| `autopilot state` | rename → `autopilot status` |
| `state-log.jsonl` | rename → `status-log.jsonl` |
| `internal state` (controller 内部) | rename → `internal status` or context で `state` 容認 |

### 7.2 mail / event / message → 4 階層

```
mailbox (.mailbox/<session>/)         ← directory
  └─ inbox (.mailbox/<session>/inbox.jsonl)  ← file
      └─ mail (1 line of inbox.jsonl)         ← entry
          └─ event (mail.event field)         ← field
```

- `message` 語を spec から液化、`mail` に統一
- 4 階層を vocabulary table の 4 entity (mailbox / inbox / mail / event) で明示

### 7.3 events directory (`.supervisor/events/`) 完全廃止

- 新 architecture で `.supervisor/events/` directory を file system レベルで使わない
- 過去 event は `.audit/<run-id>/` の audit snapshot に記録
- mailbox event は inbox.jsonl 1 本に集約
- 第 4 弾 cleanup で既に `rm -f .supervisor/events/*` 実施、設計上も正式廃止

### 7.4 制御系 4 語 → administrator 統一

| 旧用法 | 新方針 |
|---|---|
| `administrator` (191) | canonical 維持 |
| `orchestrator` (51) | spec から液化、ただし「旧 autopilot-orchestrator.sh」と backtick 引用は OK |
| `controller` (39) | 旧 type 名として backtick + 「廃止予定」明示、それ以外は spec から液化 |
| `supervisor` (18) | 旧 su-observer rebrand 前 type 名として明示、spec で role としては使わない |

### 7.5 worker vs workflow (Round 6 + 10 統合)

| 旧用法 | 新方針 |
|---|---|
| `worker` (387、一般語) | spec から液化 |
| `worker-*` prefix (150) | agents/ specialist-* に rename 済 (Round 6) |
| `Worker session` (0) / `worker session` (3) | spec から液化 (= 「別 main session」or「`phaser` session window」と表現) |

### 7.6 step 5 重 (Round 9)

| 旧用法 | 新方針 |
|---|---|
| `step` 一般語 (716) | spec から液化、「atomic を実行」と表現 |
| `Step 0` / `Step 1` (SKILL 手順番号、33) | 公式 SKILL.md スタイル準拠、`Step 0`/`Step 1` を backtick なしで保全 (手順番号として認識) |
| `step.sh` (125) | 旧 framework file、廃止予定として backtick + 「旧」明示 |
| `step::run` (21) | 同上 |
| `atomic` (53) | canonical role |
| `lifecycle phase` (39) | atomic SKILL.md 内 4-phase (pre-check/exec/post-verify/report) を「lifecycle phase」と表現、phaser とは別 entity |

---

## 8. step 実装 = atomic skill composition (Round 6 確定、確認)

### 8.1 呼び出し chain (公式仕様 verified)

```
[user / administrator が直接 invoke]
    │ slash command
    ▼
[administrator skill] ← description あり
    │ tmux new-window + claude --plugin-dir + slash command
    ▼
[phaser-impl skill] ← 別 session window、description あり
    │ Skill(workflow-test-ready)
    ▼
[workflow-test-ready skill] ← disable-model-invocation: true
    │ Skill(atomic-test-scaffold) → Skill(atomic-green-impl) → ...
    ▼
[atomic-test-scaffold skill] ← disable-model-invocation: true
    │ Agent(specialist-prompt-reviewer) ← 必要時のみ
    ▼
[specialist-prompt-reviewer agent] ← Agent tool、subagent context
```

### 8.2 atomic SKILL.md 例 (公式仕様準拠 + vocabulary 適用)

```markdown
---
disable-model-invocation: true
allowed-tools: [Bash, Read, Edit, Agent]
---

# atomic-test-scaffold

`Step 0` lifecycle phase: pre-check
- Read $ARGUMENTS[0] (AC file)
- Verify `status` == Refined via gh project item-list

`Step 1` lifecycle phase: exec
- Generate RED test from AC
- Write to tests/...

`Step 2` lifecycle phase: post-verify
- !`bats --list tests/ | wc -l`
- !`bats tests/...`   # should FAIL (RED)
- !`git diff --name-only HEAD | grep -c '^src/'`   # src diff == 0

`Step 3` lifecycle phase: report
- !`echo '{"from":"atomic-test-scaffold","event":"step-completed",...}' >> .mailbox/$session/inbox.jsonl`
```

注: `Step 0` etc. は公式 SKILL.md スタイル準拠の手順番号で、backtick 引用 (手順番号 entity として明示)。

---

## 9. 派生する spec 反映影響 (拡大、Round 7-10 反映)

### 9.1 全面書き直し (3 file)

- `ssot-design.html` (案 3 step.sh → atomic skill composition + registry.yaml)
- `tool-architecture.html` (worker-* → workflow-* + pilot → phaser + 10 role + vocabulary 適用)
- **新規 `registry-schema.html`** (registry.yaml schema + vocabulary table + 階層図)

### 9.2 用語 rename (massive、phaser に統一 + 隠れ重複処理 + 言語 policy 適用)

全 12 spec file に影響:

| 用語変更 | 規模 |
|---|---|
| `phase-*` (file prefix) → `phaser-*` | spec 内全件 + 実 file (Phase 1 PoC 実装時) |
| `phase` (status 遷移単位) → `phaser` または `status-transition` | 499 occurrence |
| `pilot` (role) → `phaser` | 396 occurrence |
| `controller` (旧 type) → backtick 引用 + 「廃止予定」 | 39 occurrence |
| `worker` (旧用法) → 文脈で液化 (workflow / specialist / phaser session window 等) | 387 occurrence |
| `worker-*` (旧 prefix) → `workflow-*` or `specialist-*` | 150 occurrence |
| `state` → `status` 統一 | 102 occurrence |
| `transition` / `遷移` → `status-transition` canonical | 54 occurrence |
| `message` → `mail` | 10 occurrence |
| `orchestrator` → 液化 (backtick 引用のみ) | 51 occurrence |
| `supervisor` → 液化 | 18 occurrence |
| `step` (一般語) → 「atomic を実行」 | 716 occurrence (一部は keep) |

### 9.3 構造変更

- `overview.html`: 図 1 で L1 = `phaser-*` に rename + 新原則「10 role + vocabulary」追加
- `twl-mcp-integration.html`: §4 types.yaml 廃止 + registry.yaml 統合
- `deletion-inventory.html`: types.yaml + deps.yaml 廃止 + composite 廃止 + worker→specialist rename 18 件 + commands/→skills/ migration
- `rebuild-plan.html`: Phase 1 PoC に EXP-032〜038 追加
- `experiment-index.html`: EXP-032〜038 (7 件) 追加
- `sandbox-experiment.html`: atomic composition + Agent spawn EXP sequence
- `boundary-matrix.html`: 10 role 一覧 + vocabulary 適用
- `glossary.html`: 10 role 正規定義 + Authority/Reference/Derived 用語 + vocabulary 6 field schema 説明
- `README.html` + `changelog.html`: 第 5 弾 dig 履歴
- `ADR-043`: Decision section に SSoT + 命名 policy 追記

### 9.4 新規 file

- `dig-report-ssot-2026-05-13.md` (本 file、独立 dig artifact)
- `registry-schema.html` (新規、registry.yaml schema + 10 role × concern matrix + 階層図)

---

## 10. 残課題 (将来 dig / 実装段階で詰める)

### 10.1 registry.yaml 実装詳細
- audit `--vocabulary` の false positive 抑制 (文脈解析: backtick 引用、説明文の単語 vs 実 component name)
- `audit_collect()` への vocabulary section 統合
- types.py `_FALLBACK_TOKEN_THRESHOLDS` の registry.yaml 自動生成 logic

### 10.2 命名 policy の例外処理
- `Step 0` / `Step 1` (公式 SKILL.md スタイル) の vocabulary table での扱い
- 「Phase 1 PoC」「Phase 2 dual-stack」(Strangler Fig migration stage) は spec で `Phase 1` 等の backtick で「migration stage entity」として明示分離 or rename to `Stage 1` 等?
- 既存日本語表記「不変条件」「遷移」を spec 説明文に保持する場合の vocabulary entry 例外処理

### 10.3 phaser 実装詳細
- phaser SKILL.md に description 必須、AI 判断で administrator が phaser-explore vs phaser-refine vs phaser-impl vs phaser-pr を select する基準
- phaser-* の `allowed-tools` declare standard template

### 10.4 vocabulary table 拡張 schedule
- Phase 1 PoC seed: core 12 entity
- Phase 2: 隠れ重複 追加 entity (orchestrator/controller/supervisor 等の「旧 type」明示、Strangler Fig phase 等)
- Phase 3: 全 spec entity (50+ 件)

### 10.5 公式仕様 breaking change 監視
- Claude Code skill / agent / hook / monitor 公式仕様の変更監視
- registry.yaml の version field を bump して migration trail

### 10.6 命名 policy ADR
- 「ADR-045 命名 policy」を新規起票し、本 dig の Round 7-10 結果を formal ADR 化

---

## 11. core lesson (本 dig で発覚した 10 件)

1. **SSoT は階層分類が先**: concern 分離より「Authority/Reference/Derived」の 3 段階分類が前提
2. **公式仕様準拠が drift 防止の基盤**: twl 独自 type は公式 component kind と mapping 明示必須
3. **description 有/無は context budget 管理の鍵**: `disable-model-invocation: true` で外す
4. **commands legacy + skills 統合**: radical rebuild の機会、commands/ 117 件を全件 skills/ migrate
5. **specialist 呼び出しは Agent() のみ**: 公式制約、composite role は不要に
6. **hook + monitor も SSoT 一体管理**: registry.yaml に統合
7. **role-prefix で全 file 識別可能**: specialist-/phaser-/workflow-/atomic-/ref-
8. **1 entity = 1 name ルール**: pilot/phase/controller 5 重のような multi-name は SSoT 違反
9. **公式 skill name 制約**: lowercase + hyphen のみ (`_` 不可)、複合 role 名は audit false positive リスク → 1 語 role が clean
10. **隠れ重複は階層的に潜む**: state/status、mail/event/message、events/mailbox、制御系 4 語、step 5 重 etc. — 命名 policy 確立後に系統的に洗い出す

---

## 12. 次のアクション選択肢

(A) **本 dig 結果を spec 本体に反映** (`feature-dev` で 12 file + ADR-043 + 新規 registry-schema.html 反映、第 4 弾と同フロー)

(B) **命名 policy ADR (ADR-045) を先に起票** (本 dig 結果を formal ADR 化、その後 spec 反映)

(C) **vocabulary table seed 12 entity を registry.yaml に書き出し** (rename 着手前の foundation)

(D) **EXP-032〜038 を先に詳細設計** (Phase 1 PoC より前で SSoT + vocabulary 関連検証)

**Recommended**: (A) — 前回第 4 弾と同フロー (dig-report 作成 → su-compact → spec 反映)

---

## 13. doobidoo hash 保存予定

本 dig 完了時 (本 file 上書き + commit 後) に doobidoo に第 7 弾 hash として保存。前累積:
- `6ef844e9` / `74b7cdf7` / `7727b59f` (前々 session)
- `24e80e43` / `e61dd3e3` (前 session 第 0 弾)
- `6fdf1d0b` (research session)
- `3d10303e` / `4a6f90b9` / `ca37a5de` (第 1-3 弾)
- `a6d6b7c1` (第 4 弾 dig)
- `09550ec2` (第 4 弾 spec 反映完了)
- `5d6632b6` (第 5 弾 dig 第 1 部 = Round 1-6 結果)
- **(第 5 弾 dig 完成版 = Round 1-10 結果、本 file 上書き後保存予定)**
