# ADR-0012: administrator rebrand (su-* → admin-*)

## Status

**Proposed** (2026-05-15)

## Context

旧 twill plugin の supervisor / observer / compact 概念を、新 twill architecture (administrator-centric design) に rebrand する。spec で確定する命名規約。

旧:
- `su-observer` skill (`plugins/twl/skills/su-observer/`)
- `su-compact` command (`plugins/twl/commands/su-compact.md`)
- 関連 script (`plugins/twl/scripts/su-precompact.sh`, `su-postcompact.sh`, `su-session-compact.sh`)

新 architecture では `administrator` role (L0、長命 main session、user 代理、Project Board status polling) が一元化された supervisor 役割を担う。glossary.html `§11. forbidden 旧用語 vs canonical 新用語` table で `su-observer → administrator` rebrand は確定済 (rebrand 前の旧 type 名として明示時のみ例外)。

ただし `su-compact` (command) の rebrand は spec 内未明示 (gap)。本 ADR で確定する。

## Decision

新 twill architecture における命名規約:

1. **`su-observer` (skill) → `administrator` (role)** — 既確定 (glossary.html §11)
2. **`su-compact` (command) → `admin-compact` (command)** — 本 ADR で新規確定
3. **関連 script (`su-{pre,post,session}-compact.sh`) → `admin-{pre,post,session}-compact.sh`** — 機械 rename (migration phase 実施)
4. **administrator の責務に「knowledge externalization (compaction trigger)」を追加** — `admin-cycle.html` 末尾 + `monitor-policy.html` administrator scope 記述で正典化

## Rationale

- naming 統一: `su-*` prefix 撤廃、`admin-*` で administrator 配下 command を明示
- spec の整合性: `administrator` role が compaction trigger も担当することを明確化
- migration の precondition 確定: 実 rename 時の name mapping が ADR-0012 で固定
- SSoT (registry.yaml) との連動: `admin-compact` entry を `components` section に新設 (本 ADR Decision 4)

## Consequences

### Positive

- 命名統一による cognitive load 低減
- migration phase の name mapping 明確化
- glossary / registry.yaml / admin-cycle / monitor-policy の cross-reference 整合

### Negative / Trade-offs

- 実 rename は migration phase で実施 (本 ADR は spec 規定のみ、実装変更なし)
- 旧 `su-*` reference が code / doc に残存する間、互換性 alias の判断が必要 (migration phase で個別検討)

### Implementation timing

- 本 ADR は **Proposed** status で起票、実 rename は migration phase で実施
- migration phase で:
  - `su-* → admin-*` 機械 rename (file / script / command)
  - alias 維持判断 (互換性 vs hard cut)
  - ref-invariants.md / pitfalls-catalog / SKILL.md 内の旧 reference 更新

## Related

- `architecture/spec/glossary.html` §11 (deprecated table、本 ADR で `su-compact → admin-compact` 行追加)
- `architecture/spec/registry.yaml` components (本 ADR で `admin-compact` entry 新設)
- `architecture/spec/admin-cycle.html` (§11 補足 administrator 責務 — knowledge externalization 追記)
- `architecture/spec/monitor-policy.html` (administrator scope に compaction trigger 注記)
- 旧 ADR (`architecture/archive/decisions/ADR-0006〜0011a/0011b`) — 本 ADR は新 architecture ADR の最初 (ADR-0012)

## Supersedes

なし (新規)

## Superseded by

なし
