# ADR-024: refined を label から Status field へ移行 + Todo→Refined→In Progress 遷移 gate

**Status**: Accepted
**Date**: 2026-04-24
**Issue**: #943
**Epic**: #944 (Phase AA)
**Supersedes**: 暗黙的に label-based gate（ADR-006 / ADR-013 を補強）
**Related**: ADR-006 (project-board-mandatory), ADR-007 (cross-repo), ADR-017 (co-issue v2), #940 (specialist review skip 安全網)

---

## Context

従来 `refined` (小文字) は GitHub **label** で管理されていた。しかし以下の問題が観察された:

1. **label は複数付与可能** → `refined` の一意性が弱い（検索で漏れ得る）
2. **Project Board Status とラベルの二重管理** → 同じ lifecycle を 2 箇所で表現
3. **gate 実装が label 付与 timing に依存** → `pre-bash-refined-label-gate.sh` が label check しているが、Status field の方が atomic に判定できる

## Decision

`refined` の管理を GitHub Project Board の **Status field** (`Refined`、先頭大文字) に移行する。

### Status field 設計

| Status | 意味 | gate |
|---|---|---|
| `Todo` (default) | 新規 Issue、specialist review 未完了 | - |
| `Refined` | 3 specialist review 完了 (critic/feasibility/codex-reviewer) | `Todo` → `In Progress` **直接遷移 禁止** |
| `In Progress` | Worker 実装中 | Worker spawn 時 `Status=Refined` **MUST** 検証 |
| `Done` | PR merged + Issue closed | - |

### 責任境界（#943 vs #940）

- **#943 gate**: `Status=Refined` の有無のみ確認する。phase-review の内容（specialist review skip など）は**検証しない**。
- **#940 gate**: specialist review の実施内容を検証する（実装中の安全網）。
- 両 gate は直交し、互いに補完する。

### Cross-repo Issue の扱い（R5 Option A）

Project Board は `twill-ecosystem` にリンクされた repo の Issue のみ Status 管理可能。外部 repo の子 Issue は Board 登録不可なため、以下のフォールバック判定を採用:

1. **Step 1**: Issue が Project Board に登録済みか check
2. **Step 2a (Board 登録済み)**: Status field を fetch、`Status == Refined` で allow、それ以外 deny
3. **Step 2b (Board 未登録 = cross-repo Issue)**: `refined` label の存在を check、label あり = allow、label なし = deny
4. **Step 3 (API 障害等)**: deny + actionable error message

### Dual-write 期間（Phase 1）

Phase B 移行まで **label と Status を dual-write** する。書き込み順序: **label 先 → Status 後**。

理由: Status を先に書くと、Status=Refined を見た autopilot が label 付与前に早期 spawn する race の可能性がある。

### fail-closed 設計

Status gate は fail-closed を採用:
- API 障害時: retry 3 回 with exponential backoff (1s/2s/4s)、3 連続失敗 → deny + actionable message
- override: `--bypass-status-gate` フラグ（su-observer 承認必須、PR description に理由記載 MUST）
- observability: `/tmp/refined-status-gate.log` に deny event を append

### cache 戦略（Phase 分離）

- **Phase 1 (本 Issue)**: fresh API call（gate の即時性を優先、cache なし）
- **Phase B (別 Issue)**: `/tmp/refined-status-cache-<pilot-pid>.json` TTL 5分 cache（bash/Python 共有、invalidation = Status write 直後 + TTL）

## Consequences

### Positive

- Status field は一意であり、state machine として自然（GitHub UI / Project View で可視化しやすい）
- gate が atomic に判定できる（GraphQL mutation で atomic write）
- lifecycle が Board 上で一元管理される

### Negative / Risks

- **R1**: hot path API rate limit（Phase B で cache 導入により解消予定）
- **R4**: breaking change: pre-seed bypass invariant が 2 層になる（hook + launcher）
- **R5**: cross-repo Board scope 制約（Option A の label fallback で回避）
- **R8**: 既存 `layer-d-refined-gate.bats` は Phase 1 では label write 継続により PASS 維持

## Implementation

- `plugins/twl/scripts/hooks/pre-bash-refined-status-gate.sh` (新規)
- `plugins/twl/scripts/autopilot-launch.sh` (L200 付近に Status pre-check 追加)
- `cli/twl/src/twl/autopilot/launcher.py` (`WorkerLauncher.launch()` に Status pre-check 追加)
- `plugins/twl/scripts/project-board-refined-migrate.sh` (新規、migration script)
- `plugins/twl/skills/workflow-issue-refine/SKILL.md` (Step 6' に dual-write 追加)
- `plugins/twl/commands/project-board-status-update.md` (target_status パラメータ化)

## Phase B（別 Issue 起票予定）

以下のいずれかの条件を満たした時点で su-observer が自動起票:
- (a) Status=Refined 経由 Done 累計 5 件以上
- (b) Phase 1 merge から 2 Wave 経過
- (c) su-observer による明示的 approval

Phase B 内容: `pre-bash-refined-label-gate.sh` deprecate / 削除、label write 削除（Status のみ）、cache 導入。
