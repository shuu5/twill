# ADR-037: Issue 作成 flow 大原則の正典化と enforcement 階層

## Status

Proposed (2026-05-08)

## Issue

#1578

## Related

- ADR-024 (Refined transition gate)
- ADR-014 (supervisor redesign)
- ADR-013 (observer first-class)
- ADR-031 (observer self-supervision)
- ADR-029 (shadow rollout pattern)
- epic #1557 (Refined 遷移 enforcement — 本 ADR の補完 layer)

## Supersedes

なし (新規)

---

## Context

twill の大原則「**co-explore → Todo → co-issue → Refined → co-autopilot**」は SKILL.md 文言のみで支えられ、ADR/spec/invariant 層には正典化されていない。technical layer (hook/MCP) も Issue 起票 flow をガードしておらず、observer/Pilot/PR review 起点の `gh issue create` が無防備に通過していた。本 session 含め少なくとも 5 件の違反 (#1552/#1554/#1577/#1549/#1551) が観察され、すべて explore-summary 不在のまま Issue が起票された。

epic #1557 は Refined 遷移を gate するが、Issue 起票自体は Out of Scope と明記されていた:

> #1557 Out of Scope:
> - 既存 PR review-derived Issue 経路の起票時 explore-summary 必須化 (bypass #6)
> - Pilot 自己起票時の self-refine 抑制

本 ADR は #1557 の補完 layer として、Issue 起票 flow に正典化と technical enforcement を導入する。

---

## Decision

### 大原則 (SHALL)

新規 Issue の起票 (`gh issue create`) は、以下のいずれかの precondition を満たさなければならない (SHALL):

1. **co-explore Step 1 bootstrap path**: `TWL_CALLER_AUTHZ=co-explore-bootstrap` env marker + `/tmp/.co-explore-bootstrap-<cksum>.json` state file
2. **co-issue Phase 4 create path**: `TWL_CALLER_AUTHZ=co-issue-phase4-create` env marker + `.controller-issue/<session-id>/explore-summary.md` 存在
3. **既存 co-issue session in-flight path**: `/tmp/.co-issue-phase3-gate-<cksum>.json` 存在 (既存 phase3-gate.sh が判定)
4. **明示的 bypass path**: `SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='<reason>'` (intervention 記録 MUST)

これら以外の経路 (observer 直接 / Pilot 直接 / PR review 直接 / 手動) は deny される。

### enforcement 階層 (3 Tier)

| Tier | 仕組み | 守備範囲 | failure mode |
|---|---|---|---|
| Tier 1 | `pre-bash-issue-create-gate.sh` (Bash hook) | Bash matcher で `gh issue create` を intercept | fail-closed (deny) |
| Tier 2 | `mcp__twl__validate_issue_create` (MCP tool) | 構造化 evidence check + observability | initial: shadow log only (ADR-029 shadow rollout); future Phase 2: deny |
| Tier 3 | SKILL.md 文言 (LLM 判断) | 4 controller (su-observer / co-issue / co-explore / co-autopilot) | reactive |

### Tier 2 rollout 方針 (ADR-029 shadow rollout 踏襲)

`mcp__twl__validate_issue_create` は ADR-029 Decision 6 の shadow rollout 3-step (log → audit → deny) を本 Issue ゲート tool にも適用する。初期は `outputType: "log"` で shadow mode (Bash hook が primary enforcement)。Phase 2 で `outputType: "deny"` に昇格 (後継 Issue で追跡)。

### bypass override

- `SKIP_ISSUE_GATE=1` + `SKIP_ISSUE_REASON='...'` の併用 MUST
- `SKIP_ISSUE_GATE=1` のみ (SKIP_ISSUE_REASON 欠落) は deny する
- intervention log: `/tmp/issue-create-gate.log` に append (`[ts] BYPASS reason=... cmd_hash=...`)
- su-observer による retroactive review SHOULD (Wave 完了時、bypass 5+ 件/Wave で alert)

### fail-open 設計 (Known Limitation R1)

- JSON 不正・ツール名不一致時: `exit 0` (no-op) — hook 不能時に enforcement が外れる
- **理由**: fail-closed (exit 2) は hook 誤設定時に gh issue create が完全に使えなくなるリスクがある
- **緩和**: Tier 2 MCP tool が二重チェック (shadow → deny で補完)

### Out of Scope

- **GraphQL 経由 bypass** (`gh api graphql -f query='mutation {createIssue...}'`): Bash matcher 範囲外。後継 Issue で追跡可能性確保
- **シェル変数展開・エイリアス経由**: 文字列マッチの限界。同上
- **CI/cron** (.github/workflows/*.yml): Claude Code hook の対象外。`TWL_CALLER_AUTHZ=ci` + `SKIP_ISSUE_REASON='ci-automated'` で許可

---

## Consequences

### Positive

- 大原則が ADR/spec/invariant に正典化され、技術 enforcement と整合
- observer/Pilot/PR review 起点の bypass が技術的に block される
- intervention log により bypass 履歴が監査可能
- co-issue Phase 4 path の explore-summary precondition が defense-in-depth で強制される

### Negative / Risks

- **R1**: fail-open (JSON 不正時) — 緩和: Tier 2 MCP tool で補完 (上記参照)
- **R2**: env marker spoofing (`TWL_CALLER_AUTHZ=co-explore-bootstrap` 手書き) → state file 併用で軽減
- **R3**: 軽微 config 起票での bypass overhead → SKIP_ISSUE_GATE protocol で吸収
- **R4**: GraphQL 経由 bypass → Out of Scope、後継 Issue で追跡
- **R5**: hook 未登録罠 (#1561 で発見) → AC で settings.json/deps.yaml 登録を強制 (AC4/AC5)

---

## Implementation

- `plugins/twl/scripts/hooks/pre-bash-issue-create-gate.sh` (新規) — Tier 1 Bash hook
- `plugins/twl/tests/bats/scripts/pre-bash-issue-create-gate.bats` (新規、12 シナリオ S1-S12)
- `cli/twl/src/twl/mcp_server/tools.py` の `twl_validate_issue_create_handler` 追加 — Tier 2 MCP tool
- `.claude/settings.json` の PreToolUse Bash hooks に append (新 hook + mcp_tool)
- `plugins/twl/deps.yaml` の scripts セクションに `pre-bash-issue-create-gate` entry 追加
- `plugins/twl/refs/ref-invariants.md` に **Invariant P** 追加 (不変条件 O の次)
- `plugins/twl/skills/co-explore/SKILL.md` Step 1 修正 (bootstrap state file 書込み + env marker)
- `plugins/twl/skills/co-issue/SKILL.md` Phase 4 [B] 修正 (env marker 設定)
- `plugins/twl/agents/su-observer/SKILL.md` MUST NOT セクション追加
- `plugins/twl/skills/co-autopilot/SKILL.md` precondition 追加
- `plugins/twl/refs/intervention-catalog.md` Layer 1 パターン 13 追加 (SKIP_ISSUE_GATE bypass protocol)
