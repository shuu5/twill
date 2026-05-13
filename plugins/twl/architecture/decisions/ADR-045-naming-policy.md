# ADR-045: twill plugin 命名 policy — 1 entity = 1 name + vocabulary 6 field schema + 10 role 体系

## Status

Proposed (2026-05-13、第 5 弾 dig 由来、ADR-043 §8 を formal ADR 化)

**Related**: [ADR-043: twill plugin radical rebuild](ADR-043-twill-radical-rebuild.md) Decision §8 + §9 を本 ADR で formal 化。ADR-044 (chain SSoT 統一、案 4 registry.yaml) と同期。

**References**: `architecture/spec/twill-plugin-rebuild/registry-schema.html` §1.5 + §4 + §7 + §8、`architecture/spec/twill-plugin-rebuild/glossary.html` §4 + §11、`architecture/spec/twill-plugin-rebuild/dig-report-ssot-2026-05-13.md` §2

---

## Context

### 経緯

2026-04〜2026-05 の twill plugin 運用で **用語多重化** の構造的欠陥が顕在化:

- **pilot / phase / phase-* (file prefix) / controller / pilot-phase**: 5 重 (~934 occurrence)
- **worker / worker-* (file prefix)**: 5 重 (~537 occurrence)
- **step (一般語) / step.sh / step::run / Step 0 (公式手順番号) / lifecycle phase**: 5 重 (~716 occurrence)
- **agent (一般語) / Agent (公式 tool) / agents/ (公式 directory) / specialist**: 4 重
- **tool (twl role) / Tool (公式) / tool-* (prefix) / tooling**: 4 重
- **state / status**: 2 重 (~102 occurrence)
- **mail / event / message**: 3 重 (~10 occurrence)
- **events directory (.supervisor/events/)**: 1 重 (旧設計)
- **制御系 4 語 (administrator / orchestrator / controller / supervisor)**: 4 重 (~108 occurrence)

これらは **「1 entity を複数 name で参照」** を許容した結果、`twl audit` での命名衝突検出が不能、role 名混乱、spec drift を生む構造的欠陥となった (横断要因 F-4)。

### 検出経緯

第 5 弾 dig (2026-05-13、10 round × 33+ question、dig-report-ssot-2026-05-13.md) で systematic に洗い出し:

- Round 7: 命名 policy の core 設計 (1 entity = 1 name + vocabulary 6 field schema)
- Round 8: 公式名衝突回避 + 言語 policy + role 1 語化
- Round 9: L1 role を `pilot-phase` (複合) → `phaser` (1 語) に最終確定
- Round 10: 隠れ重複 SSoT (state/mail/events/制御系 4 語) の系統的解消

### 公式 Claude Code 制約 (verified)

- **skill name**: lowercase letters + numbers + hyphens のみ、`_` 不可 (max 64 chars) — [skills docs verbatim](https://code.claude.com/docs/en/skills)
- **Agent tool**: subagent spawn の唯一経路、subagent は subagent spawn 不可 — [sub-agents docs verbatim](https://code.claude.com/docs/en/sub-agents)
- **disable-model-invocation: true**: description が context budget に乗らない、subagent へのプリロードも防ぐ — skills docs verbatim
- **plugin 6 component kind**: skills / agents / hooks / MCP / LSP / monitors — [plugins-reference](https://code.claude.com/docs/en/plugins-reference)

---

## Decision

twill plugin の命名 policy を以下 6 項目で formal 化する:

### 1. 「1 entity = 1 name」ルール

各 entity (role / 重要 non-role entity) は **1 つの canonical name** を持つ。

- vocabulary table (`plugins/twl/registry.yaml` の `glossary` section) を **Authority SSoT** として使用
- `twl audit --vocabulary` (Section 11、新規) で **word boundary 厳密検出** + 機械検証
- 違反は severity: warning として detect、spec / code / docs で canonical に書き換え要求
- 歴史的引用 (旧 entity 名の backtick 引用 + 「旧」明示) は context exclude として false positive 抑制

### 2. vocabulary entry 6 field schema

各 vocabulary entry は以下の 6 field を持つ:

| field | 型 | 必須 | 説明 |
|---|---|---|---|
| `canonical` | string | 必須 | 唯一の正規名 (英語 hyphen-kebab、`_` 不可) |
| `aliases` | string[] | 任意 | 許容同義語 (audit で warn しない) |
| `forbidden` | string[] | 任意 | 禁止同義語 (audit で word boundary 厳密 detect、severity: warning) |
| `context` | string | 必須 | entity が属する文脈 (role level / directory / 用途) |
| `description` | string (multiline) | 必須 | 自由記述 (日本語可、ただし entity 参照は backtick + 英語 canonical) |
| `examples` | string[] | 推奨 | 実 file 名 or 実 entity 名の例示 |

実装例:

```yaml
phaser:
  canonical: phaser
  aliases: []
  forbidden: [pilot, phase, controller, pilot-phase]
  context: L1 role
  description: |
    別 session window で動作する controller。
    administrator が Project Board status に応じて 1 phaser を spawn。
    各 phaser は 1 つの status 遷移 (`status-transition`) を担当。
  examples: [phaser-explore, phaser-refine, phaser-impl, phaser-pr]
```

### 3. 10 role 体系

twill plugin の component を 10 role に分類:

| # | role | prefix | location | description 有無 |
|---|---|---|---|---|
| 1 | `administrator` | (singleton) | `skills/administrator/` | 有 |
| 2 | `phaser` | `phaser-` | `skills/phaser-*/` | 有 |
| 3 | `tool` | `tool-` | `skills/tool-*/` | 有 |
| 4 | `workflow` | `workflow-` | `skills/workflow-*/` | 無 (`disable-model-invocation: true`) |
| 5 | `atomic` | `atomic-` | `skills/atomic-*/` | 無 (同上) |
| 6 | `specialist` | `specialist-` | `agents/specialist-*.md` (公式 directory) | 有 (公式仕様必須) |
| 7 | `reference` | `ref-` | `refs/ref-*.md` | 概念外 |
| 8 | `script` | event-based | `scripts/hooks/<event>-*.sh` | 概念外 |
| 9 | `hook` | (registry entry) | `hooks/hooks.json` | 概念外 |
| 10 | `monitor` | (registry entry) | `monitors/monitors.json` | 概念外 |

詳細 matrix (allowed-tools / can_spawn / 公式仕様根拠 / vocabulary entry の 4 追加 column): `architecture/spec/twill-plugin-rebuild/registry-schema.html` §3 を参照。

### 4. 公式 Claude Code 名衝突回避

公式名と twl 内部 entity の表記を以下で区別:

| 公式名 | spec での書き方 | twl 内部 entity 対応物 |
|---|---|---|
| `Agent` (tool) | 大文字始まり + backtick | `specialist` (role)、`agents/` (directory) |
| `Skill` (tool) | 大文字始まり + backtick | (twl 側 entity なし、機構名として `Skill` で OK) |
| `Tool` (abstract) | 大文字始まり + backtick | `tool` (role、小文字 + tool-* prefix で識別) |
| `Bash`, `Edit`, `Read`, `Write` etc. | 大文字始まり + backtick | (twl 側 entity なし) |
| `Plan` / `Explore` (agent type) | 大文字始まり + backtick | (twl 側 entity なし) |

### 5. 言語 policy

- **canonical name**: 英語 hyphen-kebab、`_` 不可 (公式 skill name 制約 verified、registry.yaml YAML key を含む全て統一)
- **説明文 / description field**: 日本語可、ただし entity 参照時は backtick + 英語 canonical
- **既存日本語表記** (「不変条件」「遷移」等): spec 説明文内では OK、registry.yaml canonical は英語 (`invariant` / `status-transition`)

### 6. migration-stage entity (Strangler Fig 例外)

Strangler Fig migration の phase 番号 (`Phase 1 PoC` / `Phase 2 dual-stack` / `Phase 3 cutover` / `Phase 4 cleanup`) を独立 entity として vocabulary table に登録:

```yaml
migration-stage:
  canonical: migration-stage
  aliases: []
  forbidden: []
  context: Strangler Fig migration phase (公式スタイル backtick + 大文字で例外扱い)
  description: |
    Strangler Fig migration の `Phase 1 PoC`/`Phase 2 dual-stack`/
    `Phase 3 cutover`/`Phase 4 cleanup` を migration-stage entity として
    vocabulary table に登録、`phase` forbidden audit から除外。
  examples: ["`Phase 1 PoC`", "`Phase 2 dual-stack`", "`Phase 3 cutover`", "`Phase 4 cleanup`"]
```

これにより `phase` の forbidden detect (canonical = `phaser`、forbidden = `pilot`/`phase`/`controller`) と区別される。

---

## Consequences

### Positive

1. **vocabulary 機械検証可能化**: `twl audit --vocabulary` で命名衝突を word boundary 厳密検出、spec / code / docs の drift を CI で防止
2. **role 階層明確化**: 10 role を Authority SSoT として確定、各 file の role 判定が自動化
3. **公式仕様 forward-compatibility**: 公式名 (`Agent`/`Skill`/`Tool`) との backtick による区別で、公式仕様の breaking change を最小影響に
4. **AI による drift 防止**: registry.yaml 1 file + 実 file の編集だけで構造維持、AI が複数 file 間で同 entity の異なる name を使う drift を機械的に阻止

### Negative / Trade-offs

1. **既存 codebase の rename コスト**: pilot/phase/controller 5 重 + worker 5 重 + step 5 重等 ~2000+ occurrence の rename が必要 (Strangler Fig `Phase 3 cutover` で実施予定)
2. **migration-stage entity 例外の文脈判断**: `Phase 1` (migration_stage) vs `phase` (forbidden) の audit 区別は false positive リスクあり、context exclude logic の精度が必要 (EXP-038 で実機検証)
3. **historical reference の保全**: 旧 entity 名 (`co-autopilot` 等) の backtick 引用は許容するが、過剰な保全は audit false positive を生む

### Migration Path

`Phase 1 PoC` (Day 1-3):
- `plugins/twl/registry.yaml` 新規作成 + glossary section seed (core 12 entity)
- `twl audit --vocabulary` helper (Section 11) 実装、bats EXP-038 PASS

`Phase 2 dual-stack` (Day 4-7):
- vocabulary table 拡張 (隠れ重複 entity 追加、orchestrator/controller/supervisor 旧 type 明示)
- 旧 entity 名 (pilot/worker/state/step.sh 等) の段階的 rename

`Phase 3 cutover` (Day 8-11):
- ~2000+ occurrence の用語 rename 完遂
- 実 file rename (`skills/phase-*` → `skills/phaser-*`、`agents/worker-*` → `agents/specialist-*`)
- `twl audit --vocabulary` warning 0 件達成

`Phase 4 cleanup` (Day 12-14):
- 本 ADR を Accepted 化
- vocabulary table を 50+ entity に拡張、全 spec entity 登録

---

## Alternatives Rejected

1. **複合 role 名** (`pilot-phase` 試案、Round 8): false positive audit リスクが高い (例: `pilot` 単独語と `pilot-phase` の word boundary 区別が複雑)。Round 9 で 1 語 `phaser` に統一。
2. **`_` 許容** (Python snake_case 互換): 公式 skill name 制約 verified で `_` 不可。registry.yaml YAML key も統一して英語 hyphen-kebab に確定 (`migration_stage` → `migration-stage` rename)。
3. **vocabulary table を別 file (vocabulary.yaml) に分離**: registry.yaml 統合 SSoT 設計 (案 4、ADR-043 §5 + ADR-044) と矛盾。registry.yaml glossary section として統合。

---

## Verification

本 ADR の機械検証は以下 EXP で実施:

- **EXP-032**: registry.yaml audit (重複 concern 検出 + prefix↔role 整合 + forbidden 使用検出) — bats unit
- **EXP-034**: registry.yaml ↔ 実 SKILL.md frontmatter 整合性 — bats unit
- **EXP-038**: `twl audit --vocabulary` の命名衝突検出 (`phaser` forbidden list + 公式名 false positive 抑制 + migration-stage entity 例外) — bats unit

`Phase 1 PoC` 着手前に EXP-032 + EXP-034 + EXP-038 PASS 必須。

---

## Supplement

詳細仕様は以下 spec file を参照:

- `architecture/spec/twill-plugin-rebuild/registry-schema.html` §4 (vocabulary 6 field schema) + §7 (公式名衝突回避) + §8 (命名 policy + 1 entity = 1 name) + §9 (変更管理)
- `architecture/spec/twill-plugin-rebuild/glossary.html` §4 (命名 policy 用語) + §11 (用語廃止リスト)
- `architecture/spec/twill-plugin-rebuild/dig-report-ssot-2026-05-13.md` §2 (命名 policy 詳細、Round 7-10)

---

## Status timeline

- 2026-05-13: Proposed (第 5 弾 dig 由来、ADR-043 §8 + §9 を formal ADR 化)
- (予定) `Phase 1 PoC` EXP-032/034/038 全 PASS 後: Accepted

## Related

- ADR-043: twill plugin radical rebuild (本 ADR の origin、Decision §8 + §9 を formal 化)
- ADR-044: chain SSoT 統一 (案 4 registry.yaml、本 ADR と同期、未起票)
- Inv U (ref-invariants.md): Atomic skill verification (旧 Step verification framework、本 ADR の命名 policy 由来 rename)
- doobidoo hash: `dcc7511a` (第 5 弾 dig 完成版 Round 1-10)
