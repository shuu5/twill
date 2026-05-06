# ADR-034: Autonomous Wave Chain Reliability Architecture

## Status

Accepted

## Amends

ADR-014 Decision 4（Wave 完了時の自動外部化）step 4 では `su-observer が Wave N+1 の Issue を co-autopilot に渡して spawn する` と明記している。本 ADR Decision 4（Observer role redefinition）はこの spawn 責務を `wave-progress-watchdog.sh`（Layer 2）に委譲する。su-observer は spawn 責任を持たず、監視・通知・報告に専念する（ADR-014 Decision 4 の部分改訂）。

## Context

### 観測された事故（2026-05-05〜06）

Wave N → Wave N+1 自動連鎖が LLM judgment 依存のため、再発性事故が繰り返されている。

1. **Wave 45 → 46 で 23h 放置事故**: Wave 45 の 4 PR が 2026-05-05 14:18-14:22 JST に全 merge 完了。observer は Pilot の自然 idle を待っていたが、Pilot は summary mode で残留し続け 23h 経過。2026-05-06T04:49Z にユーザー指摘で気付き手動 spawn。

2. **Wave 46 → 47 で同パターン再発**: Wave 46 の 3 PR merge を Monitor が検知（2026-05-06 14:20 JST）。observer は状況を報告したが 3/3 完了後に能動 action なく idle 化。2026-05-06T06:39Z にユーザーが介入するまで停止。

3. **doobidoo memory に lesson 保存しても LLM 内で運用に落ちない**: 同 session 内で「PR merge を spawn trigger とすべき」と memory hash `3ddf2a20` に保存したが、直後の Wave 46 → 47 で再発した。

### Failure mode（実装確認済み）

| # | Failure | 確認場所 |
|---|---------|---------|
| **F1: queue stale** | `.supervisor/wave-queue.json` の `current_wave` が opt-in のため stale 化 | `spawn-controller.sh` L207-225 |
| **F2: AUTO_NEXT_SPAWN 死蔵** | `IDLE_COMPLETED_AUTO_NEXT_SPAWN=1` でも `AUTO_KILL=1` 必須 → 実運用 AUTO_KILL=0 で完全 skip | `cld-observe-any` L588-595 |
| **F3: observer LLM idle** | observer は Pilot 自然 idle を待つ設計。Pilot が summary mode 残留で idle 化しない | `su-observer` SKILL.md |

### AUTO_KILL=0 維持制約

intervention-log `2026-05-04T01:58:09Z` で確認した重要な制約:

> cld-observe-any restarted with IDLE_COMPLETED_AUTO_KILL=0 due to repeated false-positive kills of wt-co-issue windows during Phase 3/4 menu wait. Pattern: STAGNATE-600 + IDLE-COMPLETED triggered when wt enters input-waiting state with empty thinking. Issue #1375 root cause confirmed empirically.

→ **AUTO_KILL=1 への復帰は false-positive kill リスクにより不可**。AUTO_KILL=0 維持を前提制約とする。

### 利用可能な既存インフラ

- `plugins/twl/skills/su-observer/scripts/auto-next-spawn.sh`（#1155): JSON Schema validation + argv allowlist + intervention-log audit 完備 — そのまま流用可
- `cli/twl/src/twl/mcp_server/tools_comm.py`（#1034 Tier C）: mailbox `twl_send_msg/recv_msg/notify_supervisor` — 利用可
- `.supervisor/events/` 構造化 JSON event ディレクトリ: IDLE-COMPLETED 等で運用中（1045+ events）— PR-merge channel 追加可
- `plugins/twl/scripts/chain-runner.sh`: PR merge step + checkpoint 出力済み — post-merge hook 追加可
- `plugins/twl/skills/su-observer/schemas/wave-queue.schema.json`: schema 定義済み — 流用可

## Decision

Wave N → Wave N+1 の自動連鎖を以下の 5 原則で実装する:

1. **LLM judgment exclusion**: autonomous chain の critical path から LLM 判断を完全に除外する。spawn 実行の最終責任は system daemon（wave-progress-watchdog.sh）が持ち、LLM の状態・判断・応答速度に依存しない。

2. **Multi-layer signal redundancy**: chain-runner による event emission（primary signal）と gh API polling（fallback）を独立して運用し、どちらか一方が失敗してもチェーンが継続する。

3. **Dedicated executor daemon**: wave-progress-watchdog.sh が Wave spawn の責任を一手に担う専用 executor として機能する。lock file による重複 spawn 防止、AUTO_KILL=0 でも動作可能な独立デーモン設計とする（F2 解消）。

4. **Observer role redefinition**: observer（su-observer）は監視・通知・報告レイヤーに専念し、spawn 判断を持たない。mailbox + ScheduleWakeup pattern で idle 化を防ぎ、visibility を確保する（F3 部分解消）。spawn の critical path には含めない。

5. **Data SSoT enforcement**: wave-queue.json は spawn 時に強制 maintenance する。`CHAIN_WAVE_QUEUE_ENTRY` を opt-in から強制に変更し、spawn 時に `current_wave`（整数）と `queue`（次 Wave 以降のエントリ配列）を必ず populate する（F1 解消）。wave-queue.schema.json の `required: [version, current_wave, queue]` と整合する。

## Architecture

### 5-layer reliability architecture (Layer 0–4)

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 0: Data SSoT (wave-queue.json 強制 maintenance)           │
│   - spawn-controller.sh: CHAIN_WAVE_QUEUE_ENTRY を強制生成      │
│   - spawn 時に current_wave + next_wave を必ず populate         │
│   - wave-queue.json stale 問題 (F1) を解消                      │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: Primary Signal (chain-runner pr-merge event emission)  │
│   - post-merge step: .supervisor/events/wave-{N}-merged-*.json  │
│   - twl_notify_supervisor で mailbox push                       │
│   - chain-runner 自身が完了 signal を出すため確実              │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: Executor (wave-progress-watchdog.sh daemon)            │
│   - events/ inotify (Linux) / polling fallback → auto-next-spawn.sh 呼び出し │
│   - lock file で重複 spawn 防止                                 │
│   - AUTO_KILL=0 維持のまま AUTO_NEXT_SPAWN と等価機能実現       │
│   - current_wave 更新権限: wave-progress-watchdog.sh が単独保有 │
│     （Wave N+1 spawn 完了後に atomic 更新する）                 │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3: Safety Net (gh API polling fallback)                   │
│   - gh pr list --state merged を 60s 間隔で polling            │
│   - events 不在時に完了確認 → Layer 2 trigger                  │
│   - Layer 1 失敗時の last resort                                │
├─────────────────────────────────────────────────────────────────┤
│ Layer 4: Observer Reactivation (mailbox + ScheduleWakeup)       │
│   - observer が mailbox recv_msg で能動 polling                 │
│   - idle 化を防ぎ visibility 確保（spawn 責任は持たない）       │
│   - F3 解消（ただし spawn の critical path には含めない）       │
└─────────────────────────────────────────────────────────────────┘
```

### Data flow

```
Worker: chain-runner pr-merge OK
   │
   ├──→ .supervisor/events/wave-{N}-pr-merged-{issue}.json  (Layer 1)
   │         │
   │         └──→ twl_notify_supervisor (mailbox push)
   │                   │
   │                   ├──→ Layer 2: wave-progress-watchdog.sh
   │                   │     └──→ current_wave の全 PR が merged?
   │                   │           ├─ yes → auto-next-spawn.sh (lock)
   │                   │           │         └──→ Wave N+1 spawn
   │                   │           └─ no  → 次 event を待機
   │                   │
   │                   └──→ Layer 4: observer mailbox recv (報告のみ)
   │
   └──→ Layer 3: gh pr list polling (60s) — 独立 fallback
                   └──→ all merged かつ event 不在? → Layer 2 trigger
```

## Consequences

### Positive

- **Reliability**: F1/F2/F3 の 3 つの failure mode が独立 layer でそれぞれ解消される
- **Crash resilience**: observer LLM が crash しても Wave 連鎖が継続する（spawn 責任が Layer 2 daemon にある）
- **Observability**: events/ + intervention-log + mailbox の三重 audit trail により Wave 進捗を追跡可能

### Negative

- **Operational complexity**: wave-progress-watchdog.sh daemon が 1 つ増加し、起動・監視・ログ管理の運用コストが発生する
- **Migration cost**: Sub-Issue S1〜S6 の実装に ~18-24h を要する（S1: spawn-controller 修正、S2: chain-runner event emit、S3: watchdog 新設、S4: cld-observe-any bind 解除、S5: observer ScheduleWakeup、S6: gh API fallback）

## Alternatives Rejected

### AUTO_KILL=1 復帰

`cld-observe-any` を `IDLE_COMPLETED_AUTO_KILL=1` モードで再起動し、F2（AUTO_NEXT_SPAWN 死蔵）を解消する案。

**却下理由**: intervention-log `2026-05-04T01:58:09Z` で確認済み。Phase 3/4 menu wait 状態の wt-co-issue windows で STAGNATE-600 + IDLE-COMPLETED が誤発火し、正常動作中の Worker pane を kill する false-positive kill が再発した（Issue #1375 で根本原因確認済み）。AUTO_KILL=0 維持を前提制約とする。

### cld-observe-any 拡張のみ

cld-observe-any 内に PR-MERGED polling thread を追加し、F2 と F3 を同時解消する案（Design C）。

**却下理由**: cld-observe-any は既に 600+ lines であり、PR-MERGED polling thread の追加は Single Responsibility Principle 違反を招く。daemon の肥大化によりデバッグ・テストコストが増大する。また、cld-observe-any が gh API polling を内包することで「監視 daemon」と「spawn executor」の責務が混在し、将来の保守性が低下する。

### Stop hook のみ

Claude Code の `Stop` hook を利用し、chain-runner session 終了時に auto-next-spawn を直接呼び出す案（Design E）。

**却下理由**: Stop hook は Claude Code session の終了に紐付くものであり、chain-runner subprocess（Bash run_in_background）の完了とは別概念。chain-runner が Bash subprocess として実行されている場合、その完了は Stop hook を発火させない。また hooks-mcp epic (#1037) との概念的重複があり、明確な責務分離ができない。

## Risk

| Risk | 説明 | Mitigation |
|------|------|------------|
| SPOF | wave-progress-watchdog.sh の crash | cld-observe-any heartbeat-watcher と同等の monitoring + Layer 3 が safety net として機能 |
| race condition | Layer 1 と Layer 3 が同時検知 | lock file + wave-queue.json の atomic `current_wave` 更新で重複 spawn を防止 |
| gh API rate limit | polling 負荷 | 60s 間隔 polling、ETag キャッシュ活用、token pre-load によるレート制限緩和 |
| event 欠損 | chain-runner failure による Layer 1 signal lost | Layer 3（gh API polling）が backstop として独立動作し、event がなくても完了を検知 |
| spawn race | observer + watchdog の二重 spawn | wave-queue.json `current_wave` チェック + lock file による排他制御 |
| event 蓄積 | events/ が 1045+ files 確認済み | 既存 cleanup 機構と同等の retention policy を wave-progress-watchdog.sh に実装必須 |

## Related

### 関連 ADR

- **ADR-013** ([Observer の First-Class 昇格](ADR-013-observer-first-class.md)) ⚠️ Superseded by ADR-014: 介入プロトコル（Auto/Confirm/Escalate）の起源。実効定義は ADR-014 Decision 5 に継承されており、本 ADR の Layer 4 observer role redefinition はその継承版を参照する。
- **ADR-014** ([Observer → Supervisor 再定義](ADR-014-supervisor-redesign.md)): su-observer のプロジェクト常駐ライフサイクルと三層記憶モデルを確立。本 ADR が F3（observer LLM idle）を解消することで ADR-014 の Wave 管理自動化パスが実現する。
- **ADR-029** ([TWL MCP Integration Strategy](ADR-029-twl-mcp-integration-strategy.md)): mailbox（`twl_notify_supervisor / recv_msg`）の設計方針。本 ADR の Layer 1/4 は ADR-029 Tier C（tools_comm.py）を直接利用する。

### 関連 Issue

- **Epic #1425**: autonomous Wave chain reliability の親 Epic（本 ADR の設計根拠を提供）
- **S1 #1427**: spawn-controller wave-queue.json 自動 enqueue 強制（Layer 0 実装）
- **S2 #1428**: chain-runner pr-merge event emission（Layer 1 実装）
- **S3 #1429**: wave-progress-watchdog.sh 新設 daemon（Layer 2 実装）
- **S4 #1430**: cld-observe-any AUTO_NEXT_SPAWN bind 解除（Layer 2 補完）
- **S5 #1431**: observer skill ScheduleWakeup pattern + recv_msg loop（Layer 4 実装）
- **S6 #1432**: gh API polling fallback in watchdog（Layer 3 実装）
- **S7 #1433**: ADR-034 起草（本 Issue / 本 ADR）

### 推奨実装順序

```
Wave A (parallel): S1 (queue 強制) + S4 (bind 解除) + S2 (event emit) + S7 #1433 (本 ADR)
   ↓
Wave B (sequential): S3 (watchdog daemon) + S6 (gh fallback)
   ↓
Wave C (single): S5 (observer ScheduleWakeup)
```

最小 mitigation として Wave A のみで 80% の信頼性向上が見込める（F1/F2 解消 + signal source 確保）。
