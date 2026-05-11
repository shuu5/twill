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

> **Phase B 完了 (2026-05-03)**: label write は削除済み。Twill 内部 Issue は Status=Refined のみを write する。以下は Phase 1 の歴史的記録。

Phase B 移行まで **label と Status を dual-write** した。書き込み順序: **label 先 → Status 後**。

理由: Status を先に書くと、Status=Refined を見た autopilot が label 付与前に早期 spawn する race の可能性があった。

### fail-closed 設計

Status gate は fail-closed を採用:
- API 障害時: retry 3 回 with exponential backoff (1s/2s/4s)、3 連続失敗 → deny + actionable message
- override: `--bypass-status-gate` フラグ（su-observer 承認必須、PR description に理由記載 MUST）
- observability: `/tmp/refined-status-gate.log` に deny event を append

### cache 戦略（Phase 分離）

- **Phase 1 (本 Issue)**: fresh API call（gate の即時性を優先、cache なし）
- **Phase B**: cache 導入は見送り（実運用で R1 rate limit が問題にならなかったため）。将来必要になった場合は別 Issue として管理する

## Consequences

### Positive

- Status field は一意であり、state machine として自然（GitHub UI / Project View で可視化しやすい）
- gate が atomic に判定できる（GraphQL mutation で atomic write）
- lifecycle が Board 上で一元管理される

### Negative / Risks

- **R1**: hot path API rate limit（Phase B では cache 導入を見送り。実運用で問題は発生しなかった）
- **R4**: breaking change: pre-seed bypass invariant が 2 層になる（hook + launcher）
- **R5**: cross-repo Board scope 制約（Option A の label fallback で回避）
- **R8**: 既存 `layer-d-refined-gate.bats` は Phase 1 では label write 継続により PASS を維持していた。Phase B 完了後は label write が削除されたため、このテストの扱いは Phase B 完了 (Tier A/B) で対応済み

## Implementation

- `plugins/twl/scripts/hooks/pre-bash-refined-status-gate.sh` (新規)
- `plugins/twl/scripts/autopilot-launch.sh` (L200 付近に Status pre-check 追加)
- `cli/twl/src/twl/autopilot/launcher.py` (`WorkerLauncher.launch()` に Status pre-check 追加)
- `plugins/twl/scripts/project-board-refined-migrate.sh` (新規、migration script)
- `plugins/twl/skills/workflow-issue-refine/SKILL.md` (Step 6' に dual-write 追加)
- `plugins/twl/commands/project-board-status-update.md` (target_status パラメータ化)
- **#1026 (AC1+AC2) merged**: `cli/twl/src/twl/autopilot/github.py` `extract_parent_epic` + `plugins/twl/scripts/chain-runner.sh` `_transition_parent_epic_if_refined` (子 In Progress 遷移時に親 Epic Refined→In Progress を auto-fire)
- **#1070 (AC checklist auto-update) merged**: `cli/twl/src/twl/autopilot/github.py` `extract_closes_ac` / `flip_epic_ac_checkbox` / `update_epic_ac_checklist` + `plugins/twl/scripts/chain-runner.sh` `_update_parent_epic_ac_checklist` (子 Done 遷移時に親 Epic body の `- [ ] **AC{N}**` を `Closes-AC: #EPIC:ACN` 規約に従って auto-flip)

## Phase B 完了 (2026-05-03)

### 完了サマリ

- **Tier A**: read site（`pre-bash-refined-label-gate.sh`、`pre-bash-phase3-gate.sh`）から refined label 参照削除 (Sub-1)
- **Tier B**: write site（co-issue Phase 4 [B] / manual-fix-b.sh / refine-flow / lifecycle-flow）から label 付与削除 (Sub-2)
- **Tier C 残置**: cross-repo R5 fallback（`autopilot-launch.sh`、`launcher.py`、`issue-cross-repo-create.md`）は label `refined` を fallback として継続使用
- **Tier D**: doc 整合（本 Sub-3 = Issue #1293）
- **Migration**: 既存 OPEN Issue Status=Refined 一括設定 + `project-board-refined-migrate.sh --force` CI 実行 (Sub-4)

### Phase B 後の運用ルール

- **Twill 内部 Issue**: Status=Refined を SSoT として書き、`refined` label は付与しない
- **Cross-repo Issue**: `refined` label を fallback として書き続ける（ADR-024 R5 制約）
- **observability**: `/tmp/refined-status-update.log` で Status update 失敗のみ WARN

**Auto-update layer 完成 (Phase 1 範囲)**: 子 Issue → 親 Epic の Status auto-transition (#1026 AC1+AC2) と AC checklist auto-flip (#1070) の両方が autopilot 経路 (chain-runner.sh `step_board_status_update`) に組み込まれた。新規 Issue は `--parent #N` + `--closes-ac #EPIC:ACN` (issue-create.md) を指定することで Phase B 完了後の規約を full enforce できる。

## Phase C 追加 (2026-05-11)

**Status**: Planned（Epic #1625 spawn 時点で先行記載、実装は child Issue #1638 / #1639 で進行）
**Issue**: #1625 (Epic) / #1638 (Axis 1-A: Explored 新設) / #1639 (Axis 1-B: Todo→Idea rename)

> **Amendment note (4-stage 設計表 superseded)**: Phase C により旧 4-stage 設計表（## Decision §Status field 設計 L26-31）は **本 Phase C 記述に superseded** される。旧 4-stage 表は歴史的記録として保持し、新規参照は Phase C の 5-stage 表を MUST 採用。

### Context（Phase C 追加の動機）

Phase B 完了時点で 4-stage Status（`Todo / Refined / In Progress / Done`）は安定運用に到達したが、以下 2 つの観察事実から **5-stage taxonomy** への拡張が必要と判明した:

1. **co-explore 完了 Issue と未精緻 Issue が区別不能**: `Todo` Status のみでは要望/バグレポレベル（探索前）と explore-summary 完了済（refine 直前）が同列に並ぶ。`Status=Explored` option 新設で区別可能にする。
2. **`Todo` 名称が semantic 不明瞭**: `Todo` は task tracker 一般用語で、Issue lifecycle の最初期 stage の意味付けが弱い。`Idea` に rename することで「未精緻アイデア / 要望」という semantic を明示する（option_id は維持して既存 Project Board item の Status field value を保護）。

### 5-stage taxonomy

| Status | 旧名称 | option_id (planned) | 意味 | gate |
|---|---|---|---|---|
| `Idea` (default) | `Todo` | `f75ad846` (維持) | 新規 Issue、要望・バグレポ・観察記録レベル、specialist review 未完了 | - |
| `Explored` | - | TBD (#1638 完了後追記) | co-explore による explore-summary 作成完了済、refine 直前 | - |
| `Refined` | 同左 | `3d983780` | 3 specialist review 完了 (critic/feasibility/codex-reviewer) | `Idea/Explored` → `In Progress` **直接遷移 禁止** |
| `In Progress` | 同左 | `47fc9ee4` | Worker 実装中 | Worker spawn 時 `Status=Refined && state==OPEN` **MUST** 検証 (#1640) |
| `Done` | 同左 | `98236657` | PR merged + Issue closed | - |

### 遷移規則

```
Idea ─── (co-explore 完了) ──→ Explored ─┐
  │                                       │
  └─── (co-issue refine 完了) ─────→ Refined ←┘
                                  │
                                  └─── (Worker spawn) ──→ In Progress ──→ Done
```

- **`Refined` gate は Idea / Explored 双方からの遷移を許容**: co-explore を skip して直接 refine する path も継続 OK（小規模 Issue 向け）。
- **`Explored → In Progress` 直接遷移は禁止**: 必ず `Refined` 経由 MUST。
  - **この禁止は実装レベルで spawn-controller.sh の `Status != Refined` abort によって機械的に保証される**（Idea / Explored のまま spawn しようとすると Status=Refined check に失敗して abort）。
  - 追加 spawn-controller.sh 変更は #1640 (Axis 2) で `state==OPEN` AND check として補強される。
- **状態が `state=CLOSED` の場合は全分岐で abort**: closed Issue は spawn 対象から machine 的に排除（#1640 Axis 2 で実装）。

### `Todo` → `Idea` rename の根拠と影響範囲

#### 根拠

- semantic 明瞭化: `Idea` の方が「未精緻なアイデア / 要望 / バグレポ」を意味する Issue lifecycle 最初期 stage の意味を持つ。
- 5-stage taxonomy の natural 命名: `Idea / Explored / Refined / In Progress / Done` で各 stage の精緻度を単調増加させる semantic 設計。

#### option_id 維持 MUST

- `Todo` option_id (`f75ad846`) を維持したまま name のみ `Idea` に変更（#1639 Axis 1-B で `updateProjectV2Field` mutation 経由）。
- option_id 維持により既存 67+ 件の Project Board item の Status field value は無影響（field value は option_id 参照のため）。
- option_id 維持 API サポートが未検証のため、`migrate-status-5stage.sh --idea-only` 実装時に staging-equivalent な事前検証を MUST（mutation 1 件発行 → option_id 不変 assert）。失敗時は「新 Idea option 作成 + 全 item の field value 移行」方式で代替。

#### scope-of-change（影響範囲）

hardcoded `\"Todo\"` 文字列が存在する ~16 ファイル（grep 結果、実装時に再 grep して網羅性再確認、#1639 Axis 1-B で実装）:

- `plugins/twl/scripts/project-board-backfill.sh` (L80, L137) — **L80 の `select(.name == \"Todo\")` は rename 後 `\"Idea\"` に変更 MUST**
- `plugins/twl/scripts/issue-create-refined.sh` (L5)
- `plugins/twl/commands/project-board-sync.md` (L89, L96)
- `plugins/twl/commands/scope-judge.md` (L37)
- `plugins/twl/commands/warning-fix.md` (L57)
- `plugins/twl/commands/prompt-audit-apply.md` (L75)
- `plugins/twl/skills/co-self-improve/SKILL.md` (L134)
- `plugins/twl/skills/su-observer/SKILL.md` (L113, L119)
- `plugins/twl/skills/su-observer/refs/su-observer-controller-spawn-playbook.md` (L40)
- `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md` (L1071, L1086)
- `plugins/twl/refs/ref-auto-issue-board-ops.md` (L10, L42, L45, L47, L50, L57)
- `plugins/twl/architecture/decisions/ADR-006-project-board-mandatory.md` (L21)
- `plugins/twl/architecture/decisions/ADR-024-refined-status-field-migration.md` (L28-29 — 本 Phase C 記述 + 旧 4-stage 表の Amendment note で対応)
- `plugins/twl/architecture/domain/model.md` (L392)
- `plugins/twl/architecture/domain/contexts/project-mgmt.md` (L122)
- `plugins/twl/architecture/domain/contexts/autopilot.md` (L234)

### option_id 動的取得の推奨

option_id を hardcode せず、`gh project field-list` 経由で動的取得することが望ましい:

```bash
IDEA_OPTION_ID=$(gh project field-list 6 --owner shuu5 --format json \
  | jq -r '.fields[] | select(.name == \"Status\") | .options[] | select(.name == \"Idea\") | .id')
EXPLORED_OPTION_ID=$(gh project field-list 6 --owner shuu5 --format json \
  | jq -r '.fields[] | select(.name == \"Status\") | .options[] | select(.name == \"Explored\") | .id')
```

production code は field-list 動的取得を優先し、`IDEA_OPTION_ID` 定数は script 内部の最適化用途のみに留める（再発防止: Phase B で `REFINED_OPTION_ID=\"3d983780\"` hardcode から学んだ pattern）。option_id 直接参照への production refactor は #1639 Axis 1-B AC1-11 で別 Issue 化候補として扱う。

### #1516 (closed) との関係性

`#1516` (closed) は pre-spawn `Status=Refined` check の前身であり、本 Phase C では以下の補強を行う（#1640 Axis 2 担当）:

- 既存 `Status=Refined` check に `state==OPEN` の AND 条件を追加（closed Issue を spawn 対象から machine 的に排除）
- abort hint に `Status=Idea` / `Status=Explored` 専用 message を追加（Phase C 後の actionable error UX）

### child Issue 一覧（Wave U.Y option B 起票）

| child | Axis | Status (本 ADR 記述時点) | 主な変更 |
|---|---|---|---|
| #1638 | Axis 1-A (Explored 新設、既存スコープ) | Todo (Idea 相当) | migrate-status-5stage.sh `--explored-only` / co-explore SKILL Step 4 / chain-runner bats / glossary `Explored Status` / pitfalls §23 / pitfalls §19 patch |
| #1639 | Axis 1-B (Todo→Idea rename、拡張スコープ) | Todo (Idea 相当) | migrate-status-5stage.sh `--idea-only` / hardcoded \"Todo\" → \"Idea\" 置換 ~16 ファイル / migrate-status-5stage.bats 拡張 / glossary `Idea Status` |
| #1640 | Axis 2 (state==OPEN AND gate) | Todo (Idea 相当) | spawn-controller.sh `--pre-check-issue` フロー内 state==OPEN AND check / su-observer SKILL.md MUST step 更新 / spawn-controller-state-open-gate.bats / abort hint Idea/Explored 対応 |
| #1641 | Axis 3 (rescue reopen 規律) | Todo (Idea 相当) | su-observer SKILL.md PR closer 尊重 MUST 追加 / pitfalls §24 / ADR-014 Decision 5 carve-out |
| #1642 | Axis 4 (eventual consistency SOP) | Todo (Idea 相当) | su-observer SKILL.md 30s window + run check MUST / .supervisor/status-observation.log / doobidoo pitfall / aggregate-status-observation-log.sh |
| #1643 | Axis 5 (view 2 board column) | Todo (Idea 相当) | ref-project-board-views.md / verify-project-board-views.sh / view 2 UI 経由 groupBy=Status 設定実施 |

### Phase C 完了条件

- [ ] #1638 merged → `Explored` option Board に追加済 + Phase C 章末に option_id 追記済
- [ ] #1639 merged → `Todo → Idea` rename 完了 + hardcoded \"Todo\" 置換完了 + Phase C 章末の rename 状況「完了 + 新 option_id 記録」更新
- [ ] #1640 merged → spawn-controller.sh state==OPEN AND check 反映
- [ ] #1641 merged → observer rescue reopen 規律 doc + ADR-014 carve-out 反映
- [ ] #1642 merged → eventual consistency SOP + 永続ログ運用開始
- [ ] #1643 merged → View 2 groupBy=Status 設定 + 検証 script 利用可能

Phase C は全 child Issue merged + Phase C 章末の option_id 記録更新で **Status=Done** に遷移する（Epic #1625 の AC checkbox auto-flip 完遂で完了判定）。

## Phase D 補遺 (2026-05-12)

**Status**: 実装済（#1564 Sub-4）
**Issue**: #1564 / **親 Epic**: #1557

### Context（Phase D 追加の動機）

`Phase4-complete.json` は Sub-1 (#1561, hook) / Sub-2 (#1562, MCP tool) が `board-status-update Refined` evidence として glob check するが、**生成側 co-issue Phase 4 [B]/[D] path が未実装** であり schema も未定義だった。本 Phase D 補遺は以下の 3 点を正典化する:

1. `Phase4-complete.json` JSON schema の定義（schema_version=1.0.0）
2. co-issue Phase 4 [B] / [D] path への生成 step 組み込み
3. cleanup 設計方針の文書化（実装は follow-up）

### evidence taxonomy（3 種、直交）

| evidence | 生成元 | 用途 | check site |
|---|---|---|---|
| `.spec-review-session-{HASH}.json` | `spec-review-session-init.sh` (HASH=`CLAUDE_PROJECT_ROOT` cksum) | Worker spec-review 実行中 (IM-7 layer b) | Sub-1 hook / Sub-2 tool |
| **`Phase4-complete.json`** | **co-issue Phase 4 [B]/[D]（本 Phase D で組み込み）** | **refine 完了の Pilot-side marker（内部 Issue 専用）** | Sub-1 hook / Sub-2 tool |
| `refined` label | `autopilot-launch.sh _check_label_fallback` | cross-repo Issue の R5 fallback | `autopilot-launch.sh` / `launcher.py` |

3 evidence は **直交** し、いずれか 1 つでも存在すれば Sub-1 hook / Sub-2 tool は allow する設計を維持する。

**cross-repo Issue への適用範囲**: `Phase4-complete.json` evidence は **内部 Issue 専用**。cross-repo Issue（Project Board 未登録）は `refined` label を fallback として継続する（ADR-024 R5 / ADR-007 継続）。

### Phase4-complete.json JSON schema（schema_version=1.0.0）

**生成パス**: `${CONTROLLER_ISSUE_DIR:-.controller-issue}/<SESSION_ID>/Phase4-complete.json`（1-level deep — Sub-1/Sub-2 の glob `*/Phase4-complete.json` と整合）

```json
{
  "schema_version": "1.0.0",
  "session_id": "<co-issue SESSION_ID>",
  "issue_number": 1234,
  "repo": "owner/repo",
  "completed_at": "2026-05-12T00:00:00Z",
  "specialists": ["issue-critic", "issue-feasibility", "worker-codex-reviewer"],
  "report_path": ".controller-issue/<sid>/per-issue/<index>/OUT/report.json",
  "phase4_path": "[B]"
}
```

- **必須フィールド**: `schema_version`, `session_id`, `issue_number`, `repo`, `completed_at`, `specialists`, `phase4_path`
- **任意フィールド**: `report_path`（multi-issue session で `<index>` 解決が困難なケースで省略可）
- **`phase4_path`**: `"[A]"` / `"[B]"` / `"[D]"` のいずれか（Phase 4 で実行された path を記録）

### 生成タイミング

Phase 4 の各 path での生成タイミング:

| path | 生成タイミング | `phase4_path` 値 |
|---|---|---|
| [B] manual fix | `chain-runner.sh board-status-update Refined` の **直前** | `"[B]"` |
| [D] direct specialist spawn | aggregate が `status: "done"` で完了した場合のみ、step 5 直後・Step 4a done 処理に移行する前（`circuit_broken` 時は生成しない — board-status-update Refined hook は不要なため） | `"[D]"` |
| [A] retry subset | **追加しない**（orchestrator 経由で hook 発火対象外 + `.spec-review-session-*.json` が存在する） | — |

### cleanup タイミング（race condition 回避方針）

詳細は `co-issue-cleanup.md` の「Phase4-complete.json cleanup 設計方針」を参照。要点:

- co-issue 終了時に **削除しない**（autopilot T3〜T6 フェーズで参照される可能性）
- TTL 24h ベース `cleanup-stale-phase4-marker.sh` を follow-up Issue (#TBD) で実装・cron 配線
- autopilot 完了（PR merge → Done 遷移）後に TTL cleanup で削除

### `schema_version` breaking change 方針（AC8）

`Phase4-complete.json` の schema は semver で管理する:

- **1.x.y（後方互換）**: フィールド**追加**のみ可。Sub-1 glob check / Sub-2 glob check は schema 内容を parse しないため影響なし
- **2.x.y（不互換）**: フィールド rename / 削除 / 型変更を含む変更。Sub-1 / Sub-2 の glob check は version-agnostic（`*/Phase4-complete.json` の存在のみ確認）で維持するが、内容を parse する consumer（将来 enhancement）は migration plan が必要。breaking change 時は本 ADR 補遺更新 + Sub-1/Sub-2 PR を伴うこと

現行: **schema_version=1.0.0**（初版、2026-05-12 定義）
