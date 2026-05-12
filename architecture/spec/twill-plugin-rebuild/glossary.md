# glossary — placeholder

**status**: placeholder (本 session 未実装、次 session で着手予定)

> 本 file は `twill-plugin-rebuild` spec の placeholder。次 session で用語集を整備する。

## 目的

本 spec で使われる用語を 1 件ずつ定義し、既存 plugin との対応関係を明示する。新 spec 読解者が用語の意味を逆引きできるように整備する。

## 想定 outline (次 session で実装)

### 階層構造

| 用語 | 定義 | 既存対応 |
|---|---|---|
| **administrator** | L0、user 代理、長命 main session、CronCreate polling、pilot mail のみ受信 | su-observer (rebrand) |
| **pilot** | L1、phase-* SKILL.md として動作、status 遷移 1:1 担当、worker 群を spawn・mail 集約 | co-autopilot の Pilot 役割 (拡張) |
| **worker** | L2、worker-* SKILL.md として動作、別 main session、単一目的の実作業 | co-autopilot の Worker 役割 (拡張) |
| **tool** | tool-* SKILL.md、user/admin 直接 invoke、status 遷移と無関係 | co-architect/project/utility/self-improve (rebrand) |
| **phase** | status 遷移 1 個に対応する pilot SKILL.md (phase-explore / phase-refine / phase-impl / phase-pr) | (新概念) |

### 通信機構

| 用語 | 定義 | 既存対応 |
|---|---|---|
| **file mailbox** | `.mailbox/<session-name>/inbox.jsonl` + flock atomic write | session-comm.sh / mailbox lock-dir (置換) |
| **mail** | JSON Lines 1 行、`{from, ts, event, detail, heartbeat_ts}` field | tmux send-keys 経由の message (置換) |
| **pyramid 集約** | worker mail → pilot 集約 → admin に要約 mail、context 効率化 | (新概念) |

### step 機構

| 用語 | 定義 | 既存対応 |
|---|---|---|
| **step** | LLM 作業 1 単位 (test-scaffold / green-impl / check 等) | chain step (既存、framework は再設計) |
| **step lifecycle** | pre-check → exec → post-verify → report の 4 phase | (新概念、自己申告 step を置換) |
| **post-verify** | 機械検証 (test 数 / RED→GREEN / src diff 等)、step rule に従う | (新概念) |
| **step.sh** | step lifecycle framework、~80 lines | chain-runner.sh L1873-1884 (置換、機械検証追加) |

### gate 機構

| 用語 | 定義 | 既存対応 |
|---|---|---|
| **gate hook** | PreToolUse hook で phase invocation 時に前提 status verify | TWL_CALLER_AUTHZ env-marker (置換) |
| **phase-gate.sh** | gate hook handler、~30 lines、gh project item-list で status query | (新概念) |
| **status SSoT** | GitHub Project Board の Status field、6-stage | 既存 Project Board (拡張: 4→6 stage) |

### 不変条件

| 用語 | 定義 | 既存対応 |
|---|---|---|
| **不変条件 (invariant)** | system が満たすべき property、MUST レベル | 既存 A-S 19 件 + 新規 T-X 5 件 |
| **MUST / SHOULD / MAY** | RFC 2119 の level (構造的 enforce / 推奨 / 任意) | 既存 ref-invariants.md と整合 |

## 参照

- `overview.html` (各用語の初出)
- `invariant-fate-table.md` (不変条件 24 件)
- 既存 `plugins/twl/refs/ref-invariants.md` (既存 invariant SSoT)
