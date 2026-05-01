---
name: twl:su-observer
description: |
  Supervisor メタ認知レイヤー（ADR-014）。
  プロジェクトに常駐し、ユーザー指示を文脈から解釈して全 controller を spawn・観察・介入する。
  Wave 管理・知識外部化・compaction も担う。

  Use when user: says su-observer/supervisor/介入/intervention/監視/observer,
  wants to monitor a running controller session,
  wants to intervene in a Worker's state,
  wants to manage Wave planning or project-level coordination,
  wants to delegate test scenario execution to co-self-improve,
  wants to start a project-resident supervisor session.
type: supervisor
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
---

# su-observer

プロジェクト常駐のメタ認知レイヤー。ユーザーの指示を文脈から解釈して適切なアクションを自律的に選択する。

**監視対象**: co-autopilot（主）, co-issue, co-architect, co-project, co-utility, co-self-improve

**起動場所**: bare repo の main ディレクトリ（ADR-014 Decision 2）

## Step 0: セッション初期化

1. bare repo 構造を検証（main/ で起動されていることを確認）
2. `.supervisor/session.json` 確認: 存在 + active → 復帰・`claude_session_id` 更新; なし → `scripts/session-init.sh` 新規作成
2.5. `.supervisor/budget-pause.json` 確認: `status: "paused"` → Worker 状態確認 → orchestrator 再起動 → `status: "resumed"` 更新 → `>>> budget 回復: 全セッション再開完了`
3. Project Board から Todo/In Progress の Issue 一覧を取得
4. **Memory MCP（MUST）**: `scripts/step0-memory-ambient.sh` → exit 0: `.supervisor/ambient-hints.md` Read; exit 1: `observer-pitfall`/`observer-lesson`/`observer-wave` タグで memory_search → `--write` 保存 → Read
4.5. auto-memory はホストローカル補助のみ — cross-machine 知見 source として使用してはならない（MUST NOT）
5. **`refs/pitfalls-catalog.md` を Read（MUST）** — 既知の落とし穴・Memory Principles・Worker auto mode 確認方法を把握
6. **`refs/monitor-channel-catalog.md` を Read（SHOULD、Wave 管理時は MUST）** — Monitor チャネル定義と Hybrid 検知ポリシーを把握
6.5. **Monitor task 起動 MUST**: `bash plugins/twl/skills/su-observer/scripts/step0-monitor-bootstrap.sh` で出力されたコマンドを Monitor tool で実行する（cld-observe-any daemon + tail -F .supervisor/cld-observe-any.log の連携起動）
7. `>>> su-observer 起動完了。指示をお待ちしています。` を表示

## Step 1: 常駐ループ（ユーザー指示待ち）

★HUMAN GATE — Layer 1 Confirm / Layer 2 Escalate 介入が必要な場合、AskUserQuestion を起動する前にユーザー確認を取ること（`intervention-catalog.md` 参照）

ユーザーの入力を文脈から解釈し、状況に応じてアクションを選択して実行する。
**モードテーブルによる強制ルーティングは行わない**。AskUserQuestion でモード選択させない。

### supervise 1 iteration（co-autopilot 監視中の必須並行チャンネル）

- 定期 audit MUST: 5 分ごとに全 ap-/wt-/coi- window を `for WIN in $(tmux list-windows -a -F '#{window_name}' | grep -E '^(ap-|wt-|coi-)'); do tmux capture-pane -t "$WIN" -p | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Enter to select|^❯ [1-9]\.|Press up to edit queued' && echo "[MENU-WAIT] $WIN"; done` で menu/input-wait pattern スキャン（cld-observe-any 補助、`-t $WIN` 必須・全 session 対象）

**`refs/su-observer-supervise-channels.md` を Read** して実行。

> **Monitor tool 連携経路（SHOULD）**: cld-observe-any 起動時は `refs/monitor-channel-catalog.md` の「Monitor tool 連携経路（方式 A: 共有 logfile tail）」セクションを参照し、stdout を `.supervisor/cld-observe-any.log` に `tee -a` redirect した上で Monitor tool を `tail -F` で起動すること。これにより `[MENU-READY]`/`[REVIEW-READY]`/`[FREEFORM-READY]` 等の event を Monitor tool でリアルタイム受信できる（#1144）。

> **検知漏れ記録（SHOULD）**: Monitor 不在・pitfall 適用漏れ・observer 自身の介入失敗など「検知漏れ」が発生した判断ポイントでは `scripts/record-detection-gap.sh` を呼び出すこと。SHOULD — 完全自動では難しいが、介入後に気づいた場合は積極的に記録する。
> ```bash
> bash skills/su-observer/scripts/record-detection-gap.sh \
>   --type <missing-monitor|pitfall-miss|intervention-fail|proxy-stuck|kill-miss> \
>   --detail "<状況の詳細>" \
>   [--related-issue "#<N>"] \
>   [--severity <low|medium|high>]
> ```
> script は `.supervisor/intervention-log.md` に追記し、stderr に doobidoo memory_store hint を出力する。LLM は hint を読んで自身で `mcp__doobidoo__memory_store` を実行すること（#1187）。

### controller spawn が必要な場合

ユーザーが実装・作成・設計・テスト等の実行を求めた場合、**`refs/su-observer-controller-spawn-playbook.md` を Read** して実行。対話型 controller（co-issue / co-architect）の proxy 対話は **`refs/proxy-dialog-playbook.md` を Read** して実行。

### 既存セッション状態確認・問題検出・Wave 管理・過去介入記録確認が必要な場合

**`refs/su-observer-wave-management.md` を Read** して実行。
問題検出時の介入: **`plugins/twl/refs/intervention-catalog.md` を Read** して 3 層分類（Auto/Confirm/Escalate）を照合（1-hop 直接参照）。

### Wave N → Wave N+1 自動連鎖（#1155）

`IDLE_COMPLETED_AUTO_NEXT_SPAWN=1` と `IDLE_COMPLETED_AUTO_KILL=1` を同時に設定すると、`[IDLE-COMPLETED]` kill 成功後に `.supervisor/wave-queue.json` から次 Wave を自動 spawn する。

**wave-queue.json スキーマ**（`skills/su-observer/schemas/wave-queue.schema.json` 参照）:
```json
{
  "version": 1,
  "current_wave": 6,
  "queue": [{
    "wave": 7,
    "issues": [1155],
    "spawn_cmd_argv": ["bash", "plugins/twl/skills/su-observer/scripts/spawn-controller.sh", "..."],
    "depends_on_waves": [6],
    "spawn_when": "all_current_wave_idle_completed"
  }]
}
```

enqueue は `spawn-controller.sh` 起動時に `CHAIN_WAVE_QUEUE_ENTRY` 環境変数（JSON）で渡す（IF-2）。
`auto-next-spawn.sh` は `--dry-run` で動作確認可能（実際の spawn なし）。

### compaction が必要な場合

`Skill(twl:su-compact)` を呼び出して知識外部化し、`/compact` 手動実行をユーザーへ提案する（`/compact` は built-in CLI のためユーザー手動実行が必須）。

| ユーザー指示 | 動作 |
|---|---|
| `compact` / 外部化 / 記憶整理 | 状況に応じた外部化 + compaction |
| `compact --wave` | Wave 完了サマリ外部化 + compaction |
| `compact --task` | タスク状態保存 + compaction |
| `compact --full` | 全知識の外部化 + compaction |

## Step 2: セッション終了

1. 進行中の observe ループを停止
2. 未処理の介入記録を集約・保存
3. `commands/externalize-state.md` を Read → 実行（最終状態の外部化）
4. 終了をユーザーに通知

## SU-* 制約（MUST）

> **境界**: SU-1〜SU-7 は Supervisor（su-observer）固有の制約。不変条件 A-M の定義は `refs/ref-invariants.md` を参照。

| 制約 ID | 内容 |
|---------|------|
| SU-1 | 介入は 3 層プロトコル（Auto/Confirm/Escalate）に従わなければならない（SHALL） |
| SU-2 | Layer 2（Escalate）の介入はユーザー確認が MUST |
| SU-3 | Supervisor 自身が Issue の直接実装を行ってはならない（SHALL） |
| SU-4 | 同時に supervise できる controller session は 5 を超えてはならない（SHALL） |
| SU-5 | context 消費量 80% 到達時に知識外部化を開始しなければならない（SHALL）。検知手段: Claude Code の PreCompact hook（`su-precompact.sh`）が自動発火するため、hook stdout の `[PRE-COMPACT]` マーカーを観測すること。また status line の `[BUDGET-LOW]` シグナルも補助的に使用可。能動的な context 残量取得手段は現時点では未確立（#1020 追跡）。`[BUDGET-LOW]` は 2 軸独立判定（consumption-based: token残量 ≤ 40分 / cycle-based: cycle reset wall-clock `(YYm)` ≤ 5分）で発火する。`(YYm)` は次の cycle reset までの wall-clock であり token 残量ではない（#1022）。詳細: `refs/monitor-channel-catalog.md` の `[BUDGET-LOW]` セクション参照。 |
| SU-6a | Wave 完了時に結果収集と externalize-state を実行しなければならない（SHALL） |
| SU-6b | context 逼迫時またはユーザー指示時に `/compact` をユーザーへ提案しなければならない（SHOULD） |
| SU-7 | observed session への inject/send-keys は介入プロトコルに従う場合に許可（MAY） |

## 禁止事項（MUST NOT）

- Issue の直接実装をしてはならない（SU-3）
- AskUserQuestion でモード選択を強制してはならない（LLM が文脈から判断すること）
- Skill tool による controller の直接呼出しをしてはならない（cld-spawn 経由で起動すること）
- Layer 2 介入をユーザー確認なしで実行してはならない（SU-2）
- 同時に 5 を超える controller session を supervise してはならない（SU-4）
- context 80% 到達を無視してはならない（SU-5）
- Wave 完了後の externalize-state を省略してはならない（SU-6a）
- `/compact` の自動実行を試みてはならない（built-in CLI のためユーザー手動実行が必須）
- 検出結果をユーザー確認なしで自動 Issue 起票してはならない
- `--with-chain --issue N` で co-autopilot を直接起動してはならない（ADR-026、SU-3 連鎖）

## Security gate (Layer A-D) 回避は MUST NOT

**`refs/su-observer-security-gate.md` を Read** して Layer A-D ゲート定義・bypass 禁止手法・permission 拒否対応を確認すること。

2 回以上 deny が連続した場合: 即時 STOP → **`plugins/twl/refs/intervention-catalog.md` パターン 13**（Layer 2 Escalate）→ AskUserQuestion。`refs/pitfalls-catalog.md §12` 参照。
