# ADR-028: Atomic RMW Strategy for session.json

## Status
Accepted

## Context

Wave B (Pilot session da018cfc) 起動時に session.json の RMW (Read-Modify-Write) race condition が
Self-Improve 候補として観察された (doobidoo `958abe85`)。co-explore (.explore/974/summary.md) および
specialist review 4 種で実態を verify した結果、以下 4 経路の compound RMW が未保護であると判明:

| ファイル | 行 | 対象 field | パターン | 危険度 |
|---|---|---|---|---|
| `commands/autopilot-retrospective.md` | L127-130 | `retrospectives[]` (append) | `tmp=$(mktemp); jq ... > $tmp && mv $tmp` | medium |
| `commands/autopilot-phase-postprocess.md` | L75-78 | `retrospectives[].postprocess_duration_sec` (modify) | `jq ... > .tmp && mv .tmp` | medium |
| `commands/autopilot-patterns.md` | L68-71 | `self_improve_issues[]` (append) | `tmp=$(mktemp); jq ... > $tmp && mv $tmp` | medium |
| `commands/externalize-state.md` | L121-138 | `externalization_log[]` (append) | Python inline `open(file,"w")` | **HIGH** |

`externalize-state.md` は atomic rename すら行わず直接上書きしており、crash 時にファイル破損のリスクがある。

### 実 race 発生条件

通常の単一 Pilot 逐次実行 (autopilot-phase-postprocess.md:84 の逐次 MUST) では race は発生しない。
以下のシナリオが actual race 条件:
1. Phase resume / crash-recovery 時の重複実行
2. su-observer (ADR-014) の externalize-state 非同期呼出し と Pilot retrospective の並列発火
3. 将来的な並列 Phase 処理導入時の regression

## Decision

**短期 (本 ADR)**: `flock(8)` advisory lock を使用した `session-atomic-write.sh` helper を作成し、4 経路をすべて置換する。

**中期 (B-1 別 Issue)**: Python wrapper サブコマンド (`twl autopilot session add-{retrospective,pattern,externalization}`) への移行。bash flock(1) と Python `fcntl.flock()` は同一 `flock(2)` syscall で相互排他可能なため、共存期間中も lost-update は発生しない。

## Candidate Comparison

| 候補 | 利点 | 欠点 | portability |
|---|---|---|---|
| **(a) `flock(8)` advisory lock** (採用) | bash native、既存 RMW に最小変更、Python `fcntl.flock()` と相互排他可能 | macOS デフォルト非搭載 (util-linux 依存、Homebrew 必要) | Linux: ✅ / macOS: ⚠️ |
| (b) Python wrapper サブコマンド | code unification、type safety、`_atomic_write` 既存活用、OS 非依存 | 4 caller 改修必要、cold start ~50-80ms | Linux/macOS: ✅ |
| (c) `jq -i` (in-place) | — | **標準 jq に存在しない** (jq 1.7 で `Unknown option -i`) | ❌ 採用不可 |

選定基準: portability、error handling、lock granularity、bash/Python interop、既存 RMW への影響度。

候補 (c) は upstream jqlang/jq で未実装のため reject。

## Implementation

### session-atomic-write.sh

`scripts/session-atomic-write.sh` を新設:
```
session-atomic-write.sh <session_file> [jq_args...] <jq_filter>
```

内部実装:
```bash
(
  flock -x -w 10 9 || { echo "ERROR: flock タイムアウト" >&2; exit 1; }
  TMP=$(mktemp)
  jq "$@" "$SESSION_FILE" > "$TMP" && mv "$TMP" "$SESSION_FILE"
) 9>>"${SESSION_FILE}.lock"
```

### session.json field write authority matrix

ADR-018 (state-schema-ssot) の SSOT 原則を session.json write authority に拡張する:

| field | authorized writer | 経路 | 本 ADR 後の保護 |
|---|---|---|---|
| `retrospectives[]` | Pilot (autopilot-retrospective.md) | bash jq+mv | flock ✅ |
| `retrospectives[].postprocess_duration_sec` | Pilot (autopilot-phase-postprocess.md) | bash jq+mv | flock ✅ |
| `self_improve_issues[]` | Pilot (autopilot-patterns.md) | bash jq+mv | flock ✅ |
| `externalization_log[]` | Pilot/su-observer (externalize-state.md) | bash jq+mv (旧 Python) | flock ✅ |
| `session_id`, `plan_path`, etc. | Pilot (session creation) | Python `_atomic_write` | B-1 委譲 |
| `cross_issue_warnings[]` | Pilot | Python `_atomic_write` | B-1 委譲 |

### reader 側 LOCK_SH 要否

su-observer は session.json を read-only で観察する。現状の read は atomic rename 後のファイルを
読むため LOCK_SH は不要。ただし将来的に su-observer が read → externalize → write のループで
同一ファイルを扱う場合は LOCK_SH 取得を検討すること。

### B-1 統合時の Python wrapper interface (先行定義)

B-1 (Python 経路 RMW atomic 化) 実装時に追加するサブコマンド:
- `twl autopilot session add-retrospective --phase <N> --results <str> --insights <str>`
- `twl autopilot session add-self-improve --url <url> --title <str>`
- `twl autopilot session add-externalization --at <ts> --trigger <str> --path <str>`
- `twl autopilot session update-postprocess-duration --phase <N> --duration-sec <N>`

内部: `_atomic_write` + `fcntl.flock(LOCK_EX)` — bash flock(1) と同一 `flock(2)` syscall で相互排他。

## Consequences

### Positive
- 4 経路の lost-update リスクを排除
- externalize-state.md の直接上書きによるファイル破損リスクを解消
- bats integration test (tests/unit/autopilot-state-rmw/atomic-rmw.bats) で regression 防止

### Negative / Tradeoffs
- Linux 専用 (macOS では util-linux の Homebrew インストールが必要)
- 10s lock timeout: deadlock検出は弱い (flock(1) に deadlock detection はない)
- `.lock` ファイルが session.json 隣に残存する (プロセス終了後も残る — 無害だが清掃が必要な場合がある)

## Related

- ADR-003 (unified-state-file) — session.json write authority matrix の拡張 (本 ADR が Amendments として追記)
- ADR-014 (supervisor-redesign) — su-observer の externalize-state 非同期呼出しが race 発生源の 1 つ
- ADR-018 (state-schema-ssot) — SSOT 原則の session.json write authority への拡張
- Issue #974 — 本 ADR の発端、4 経路の atomic 化
- Issue B-1 — Python 経路 RMW atomic 化 (session.py:add_warning / state.py:write)
