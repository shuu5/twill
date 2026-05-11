## 終了時クリーンアップ（Phase 4 完了後）

co-issue 終了時（正常終了・エラー終了のいずれでも）に以下の一時ファイルをクリーンアップする:

```bash
# Phase 3 gate state file（hash 基準: CLAUDE_SESSION_ID）
SESSION_ID_CKSUM=$(printf '%s' "${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}" | cksum | awk '{print $1}')
GATE_FILE="/tmp/.co-issue-phase3-gate-${SESSION_ID_CKSUM}.json"
rm -f "$GATE_FILE"

# spec-review session state file（hash 基準: CLAUDE_PROJECT_ROOT — spec-review-session-init.sh と同一）
SPEC_REVIEW_HASH=$(printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}')
SPEC_REVIEW_STATE_FILE="/tmp/.spec-review-session-${SPEC_REVIEW_HASH}.json"
rm -f "$SPEC_REVIEW_STATE_FILE"
```

**hash 算出基準の注記**: 2 つのファイルは異なる hash 基準を使用する。
- Phase 3 gate: `CLAUDE_SESSION_ID` ベース（co-issue セッション固有）
- spec-review session: `CLAUDE_PROJECT_ROOT` ベース（spec-review-session-init.sh L26 と同一）

この非対称は既存設計上の都合による。統一方針は #834 (deps.yaml 関係定義) で整理予定。

## Phase4-complete.json cleanup 設計方針 (ADR-024 Phase D)

`Phase4-complete.json`（`${CONTROLLER_ISSUE_DIR}/<SESSION_ID>/Phase4-complete.json`）のクリーンアップは以下の設計方針に従う。**実装は follow-up Issue で別途扱う。**

### (a) TTL — co-issue 終了時に削除しない

co-issue 終了時に `Phase4-complete.json` を **削除しない**。TTL 24h ベースの `cleanup-stale-phase4-marker.sh`（新規）を follow-up Issue で実装し、cron 配線する。

### (b) 並行セッション isolation

`Phase4-complete.json` は `${CONTROLLER_ISSUE_DIR}/<SESSION_ID>/` 配下に配置されるため、SESSION_ID ごとに isolation される。

Sub-1 / Sub-2 の glob `*/Phase4-complete.json` は全セッションを横断してマッチするため、古いセッションの marker が残存すると次の co-issue セッションが evidence を持っていなくても hook が誤 allow するリスクがある。`cleanup-stale-phase4-marker.sh` で TTL（24h）を超えた marker を削除することでこのリスクを軽減する。

### (c) autopilot 完了まで削除しない

`board-status-update Refined` 成功後、autopilot が spawn される T3〜T6 フェーズで `Phase4-complete.json` が参照される可能性があるため、autopilot 完了（PR merge → Done 遷移）まで削除しないこと:

```
T0  co-issue Phase 4 [B]/[D] が Phase4-complete.json を生成
T1  board-status-update Refined 成功
T2  co-issue 終了（削除しない）
T3  autopilot 起動 — Status=Refined を見て spawn-controller 開始
T4  spawn-controller が In Progress 遷移を実行
T5  hook が evidence check → Phase4-complete.json で allow
T6  Worker 進行中
T7  PR merge → Done 遷移後に TTL cleanup で削除
```
