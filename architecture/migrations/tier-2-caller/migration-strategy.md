# Tier-2 Caller Migration Strategy (Issue #1032)

## Overview

ADR-029 Decision 5 — Wave 21 Phase 1+2: session_msg API 経由への caller 移行戦略。

## 対象 Caller

以下のスクリプトが `session-comm.sh inject` または直接 `tmux send-keys` を使っており、
`session_msg send` API 経由に移行する対象（Tier B: Wave 21 Phase 2+以降）。

### plugins/session

- `scripts/lib/observer-auto-inject.sh` — `tmux send-keys` L189, L195（メニューUI）
- `scripts/cld-spawn` — `inject` → `send-file` L209

### plugins/twl

- `scripts/autopilot-orchestrator.sh` — `tmux send-keys` L509（enter-only）、L942（content）
- `scripts/lib/inject-next-workflow.sh` — `inject` L158（trace 維持）
- `scripts/spec-review-orchestrator.sh` — `inject-file --wait 60` L205
- `scripts/issue-lifecycle-orchestrator.sh` — `inject-file` L368, L633, L649, L691, L702
- `scripts/pilot-fallback-monitor.sh` — `inject` L180

## 移行 API 対応表

| 旧 API | 新 API |
|--------|--------|
| `session-comm.sh inject TARGET CONTENT` | `session_msg send TARGET CONTENT` |
| `session-comm.sh inject-file TARGET FILE` | `session_msg send-file TARGET FILE` |
| `tmux send-keys -t TARGET Enter` | `session_msg send TARGET "" --enter-only` |

## 移行フェーズ

### Phase 1 (Issue #1032 — 本 PR)

- `session-comm.sh` から `tmux send-keys` 直呼びを排除（AC-1）
- `session_msg` 関数と Strategy dispatch（`TWILL_MSG_BACKEND`）を実装（AC-2, AC-4）
- `session-comm-backend-tmux.sh` / `session-comm-backend-mcp.sh` を導入（AC-4）
- `mcp_with_fallback` shadow モードで Phase 2 shadow observation を有効化（AC-5）

### Phase 2 (Issue #1033 — 別 PR)

- `TWILL_MSG_BACKEND=mcp_with_fallback` を段階的に適用
- shadow ログ（`.autopilot/mailbox/shadow-*.jsonl`）を `mcp-shadow-compare.sh` で監視
- 7 日間連続 mismatch 0 確認後に Phase 3 へ

### Phase 3 (Issue #1033 close トリガー)

- `TWILL_MSG_BACKEND=mcp` をデフォルト化
- tmux backend は whitelist（緊急 fallback）として保持

### Phase 4 (Issue #1050)

- tmux backend を非デフォルト化（手動 override のみ）
- `TWILL_MSG_BACKEND=tmux` は emergency override として残留

## rollback 手順

`rollback-plan.md` を参照。
