# Tier 2 Caller Migration Strategy

ADR-029 Decision 5 (2026-05-02 amendment) の補助ドキュメント。`tmux send-keys` 直叩きおよび `session-comm.sh::cmd_inject` 経由 caller を `mcp__twl__twl_send_msg` 経由に migrate する **Wave 21** 実装計画の詳細。

**Status**: Planning — Wave 21 実装前承認待ち
**Owner**: Tier 2 caller migration（`#1037` Tier 2 / `#1034` epic）
**Companion**: `rollback-plan.md`（同階層）

---

## 1. 背景と前提

### 既完了アーティファクト（migration の起点）

- **`tools_comm.py` の MCP mailbox hub** — `cli/twl/src/twl/mcp_server/tools_comm.py` L66-78 (`_append_atomic` flock) + L147-179 (`_send_msg_impl` ULID + jsonl append) + L182-207 (`_recv_msg_impl` since-filter polling)
- **3 MCP tool 公開済** — `mcp__twl__twl_send_msg` / `mcp__twl__twl_recv_msg` / `mcp__twl__twl_notify_supervisor`（FastMCP 経由 connected）
- **`#1101` epic CLOSED**（17 tools merged: validation 5, state 2, autopilot, comm 3）

→ **新規 backend 実装不要**。残作業は **caller 側の置換のみ**。

### 残作業の全体像

| 層 | スコープ |
|---|---|
| **Strategy 層** | `session-comm.sh` に `session_msg send/recv/ack/list` API 追加 + `TWILL_MSG_BACKEND` dispatch（`#1032` Tier B 統合） |
| **Backend 層** | `session-comm-backend-tmux.sh` 新規（既存 `cmd_inject` ロジック移動）+ `session-comm-backend-mcp.sh` 新規（`mcp__twl__twl_send_msg` 呼出 wrapper） |
| **Caller 層** | production 5 ファイル ~15 行 + session-comm.sh 経由 7 caller を `session_msg send` API に置換 |
| **Test 層** | bats integration test + shadow log compare (`mcp-shadow-compare.sh`) |
| **Lint 層** | `tmux send-keys` 直叩き禁止 lint（`twl audit` 拡張、whitelist 例外を `session-comm-backend-tmux.sh` + 緊急 kill-window 系のみに限定） |

---

## 2. Caller Inventory（実測 2026-05-02）

### 2.1 Direct `tmux send-keys` 直叩き（5 ファイル / ~9 production 行）

`grep -rn "tmux send-keys" plugins/{twl,session}/{scripts,skills}/` を `tests/` および `*.md` を除外して実行した結果。

| # | ファイル | 行 | 用途 | Migration 後 |
|---|---|---|---|---|
| 1 | `plugins/session/scripts/session-comm.sh` | 292 | `cmd_inject` 内 `-l` (literal) text 送信 | `session-comm-backend-tmux.sh` に移動 + Strategy 層 dispatch |
| 1 | `plugins/session/scripts/session-comm.sh` | 298 | `cmd_inject` 内 Enter 送信 (text 後) | 同上（同一関数内） |
| 1 | `plugins/session/scripts/session-comm.sh` | 414 | `cmd_inject_file` 内 paste-buffer 後の Enter 送信 | 同上（`cmd_inject_file` ごと backend-tmux.sh へ移動。Phase 4 で削除予定） |
| 2 | `plugins/session/scripts/lib/observer-auto-inject.sh` | 189 | observer auto-inject の選択肢番号送信 | `session_msg send "$window" "$selected_num"` 経由 |
| 2 | `plugins/session/scripts/lib/observer-auto-inject.sh` | 195 | observer auto-inject の Enter のみ送信 | `session_msg send "$window" "" --enter-only`（要 API 拡張、または skip pattern） |
| 3 | `plugins/twl/scripts/autopilot-orchestrator.sh` | 481 | Pilot loop 内 Enter 送信 | `session_msg send "$window_name" "" --enter-only` |
| 3 | `plugins/twl/scripts/autopilot-orchestrator.sh` | 914 | next workflow command 送信（fallback） | `session_msg send "$window_name" "$next_cmd"` |
| 4 | `plugins/twl/scripts/lib/inject-next-workflow.sh` | 158 | inject-next-workflow 中の skill コマンド送信 | `session_msg send "$window_name" "$_skill_safe"` + 既存 trace_log 維持 |
| 5 | `plugins/twl/skills/su-observer/scripts/budget-detect.sh` | 101 | budget 検出時の Escape 送信（緊急介入） | **whitelist 例外**（kill-window 緊急介入カテゴリ） |

> **緊急介入カテゴリ**: `tmux send-keys ... Escape` / `kill-window` / `respawn-pane` 等のセッション制御は MCP 経路で代替不能（送信先が live tmux ペイン状態のみ）。`budget-detect.sh:101` の Escape 送信は Phase 4 lint で whitelist 登録。

### 2.2 `session-comm.sh` 経由 production caller（7 ファイル）

`session-comm.sh` の `inject` / `inject-file` / `capture` / `wait-ready` を呼び出す production code。`capture` / `wait-ready` は読み取り専用のため migration 対象外、`inject` / `inject-file` のみ Strategy 層 dispatch を経由する。

| # | ファイル | 該当行 | 呼出 API | Migration 後 |
|---|---|---|---|---|
| A | `plugins/session/scripts/cld-spawn` | 209 | `session-comm.sh inject-file "$WINDOW" "$PROMPT_FILE" --wait` | `session-comm.sh send-file "$WINDOW" "$PROMPT_FILE" --wait`（API rename + Strategy dispatch） |
| B | `plugins/session/scripts/cld-observe` | 80 | `session-comm.sh capture` | **対象外**（読み取り専用、TUI 監視用途） |
| C | `plugins/twl/scripts/spec-review-orchestrator.sh` | 203 | `session-comm.sh inject-file ... --wait 60` | `session-comm.sh send-file --wait 60` |
| D | `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` | 370 | `inject-file --wait 60` | `send-file --wait 60` |
| D | `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` | 635 | `inject "$window" "$_safe_num"` | `send "$window" "$_safe_num"` |
| D | `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` | 651,693,704 | `inject "$window" ...` | `send "$window" ...` |
| E | `plugins/twl/scripts/pilot-fallback-monitor.sh` | 104-176 | `session-comm.sh` 解決 + `inject` | `send` API に追従（resolve ロジックは維持） |
| F | `plugins/twl/scripts/autopilot-orchestrator.sh` | （direct + via session-comm.sh） | 重複あり、上記 #3 と同じ scope | 同上 |
| G | `plugins/twl/skills/su-observer/scripts/budget-detect.sh` | （direct send-keys のみ） | 上記 #5 と同じ | whitelist |

> **API rename 戦略**: `inject` / `inject-file` は **Phase 4 cleanup で deprecation alias** として維持（既存 caller が `inject` を呼んでも内部で `send` に dispatch）。Phase 4 完了後に削除。

### 2.3 Markdown 内サンプル（migration 対象外）

`grep -rn "tmux send-keys" plugins/{twl,session}/skills/` の `.md` 結果（参考情報、production 動作に非関与）:

- `plugins/twl/skills/su-observer/refs/monitor-channel-catalog.md`
- `plugins/twl/skills/su-observer/refs/proxy-dialog-playbook.md`
- `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md`

→ Phase 4 で `session_msg send` 例に書き換え（lint 対象外、個別 PR で対応）。

---

## 3. Phase 別実装計画

### Phase 1: Strategy 層 + Backend 層実装（PR #1）

**目的**: `session_msg` API + 2 backend を追加し、`TWILL_MSG_BACKEND=tmux` default で既存挙動を維持。

#### 1.1 `session-comm.sh` 改修

新 API を追加し、内部で backend dispatch:

```bash
session_msg send <window> <text> [--enter-only] [--wait N]
session_msg send-file <window> <file> [--wait N]
session_msg recv <window> [--since <ulid>] [--timeout N]
session_msg ack <window> <message_id>
session_msg list <window> [--limit N]
```

dispatch ロジック（pseudocode）:

```bash
session_msg() {
  local cmd="$1"; shift
  local backend="${TWILL_MSG_BACKEND:-tmux}"
  case "$backend" in
    tmux)              source "$SCRIPT_DIR/session-comm-backend-tmux.sh"; "_tmux_${cmd}" "$@" ;;
    mcp)               source "$SCRIPT_DIR/session-comm-backend-mcp.sh";  "_mcp_${cmd}" "$@" ;;
    mcp_with_fallback) _shadow_dispatch "$cmd" "$@" ;;
  esac
}
```

#### 1.2 `session-comm-backend-tmux.sh` 新規作成

既存の `cmd_inject` / `cmd_inject_file` ロジックを **そのまま移動**（行単位 cut/paste）。`session-comm.sh` 本体には `session_msg` ディスパッチャと shim のみ残す（既存 `inject` / `inject-file` は backend-tmux 経由の deprecation alias）。

#### 1.3 `session-comm-backend-mcp.sh` 新規作成

`mcp__twl__twl_send_msg` を Python CLI 経由で呼出する wrapper:

```bash
_mcp_send() {
  local window="$1" text="$2"
  python3 -m twl.mcp_client send_msg \
    --recipient "$window" \
    --text "$text" \
    --sender "${TMUX_PANE:-unknown}" \
    --kind "inject"
}
```

> `twl.mcp_client` は新規モジュール（`cli/twl/src/twl/mcp_client/__main__.py`）。FastMCP の stdio transport を呼び出す軽量 client。`tools_comm.py` の handler を再利用するため pure Python で実装可能。

#### 1.4 Strategy 層 unit test (bats)

`plugins/session/tests/bats/session-comm-strategy.bats`:

- `TWILL_MSG_BACKEND=tmux` で既存 `cmd_inject` と等価動作
- `TWILL_MSG_BACKEND=mcp` で `_mcp_send` 経由
- 不正な値で error exit + meaningful message
- backend ファイル欠落時の fallback 挙動（`session-comm-backend-mcp.sh` 不在 → tmux fallback + WARN log）

#### 1.5 PR #1 完了条件

- `session_msg` API が `TWILL_MSG_BACKEND=tmux` で既存テスト全 PASS
- `session-comm-backend-{tmux,mcp}.sh` が独立して読み込み可能（`bash -n` PASS）
- bats unit test PASS（Strategy 層 + 各 backend 単体）
- caller 側コードは未変更（既存 `inject` / `inject-file` は alias として動作）

---

### Phase 2: Shadow Migration（PR #1 と同 PR）

**目的**: production caller を `session_msg send` API に書換 + 両 backend 並走 + shadow log 記録。

#### 2.1 caller 書換

`§2.1` および `§2.2` のテーブルに従い、5 production scripts + 7 session-comm.sh consumer を `session_msg send` / `send-file` に書換。

書換は **mechanical**（API 名のみ変更、引数構造は維持）。

#### 2.2 Shadow dispatch 実装

`TWILL_MSG_BACKEND=mcp_with_fallback` 時、`_shadow_dispatch` が以下を実行:

```bash
_shadow_dispatch() {
  local cmd="$1"; shift
  # 1. Primary: tmux backend で実際に inject
  _tmux_${cmd} "$@"
  local primary_rc=$?
  # 2. Shadow: mcp backend を dry-run（mailbox に書込のみ、tmux への副作用なし）
  TWILL_SHADOW_LOG=1 _mcp_${cmd} "$@" 2>>/tmp/twill-mcp-shadow.log
  # 3. log: tmux 送信内容と mcp dry-run 内容を timestamp 付きで shadow log に記録
  echo "$(date -u +%FT%TZ) cmd=${cmd} args=$* primary_rc=${primary_rc}" >>/tmp/twill-mcp-shadow.log
  return $primary_rc
}
```

> **設計原則**: shadow log は **副作用なし**（mcp 側は mailbox jsonl への append のみで tmux への送信は行わない）。primary（tmux）の戻り値が呼出元に伝わる。

#### 2.3 `mcp-shadow-compare.sh`（新規）

`plugins/twl/scripts/mcp-shadow-compare.sh`:

```bash
#!/usr/bin/env bash
# Shadow log と mailbox jsonl を比較、mismatch を report
# Usage: mcp-shadow-compare.sh [--since DATE] [--window NAME]

# 1. /tmp/twill-mcp-shadow.log から (window, text, timestamp) tuple を抽出
# 2. .twill/state/mailbox/<window>.jsonl の since-filter と突合
# 3. mismatch 行を JSON で stdout に出力（exit 0 = mismatch 0、exit 2 = mismatch あり）
```

> `#1225 deps-yaml-guard` の `deps-yaml-shadow-compare.sh` pattern を踏襲（既存 SSoT 再利用）。

#### 2.4 Phase 2 完了条件

- 全 production caller が `session_msg send` 経由
- `TWILL_MSG_BACKEND=mcp_with_fallback` で 1 週間以上連続稼働
- `mcp-shadow-compare.sh` 実行で mismatch 0 件（AC5-5 充足）
- shadow log の容量管理（logrotate 設定 + 自動圧縮）

> **観察期間**: ADR-029 Decision 5 で「1 週間以上」と明記。su-observer が日次で `mcp-shadow-compare.sh` を実行し、mismatch 0 件を Wave 観察に記録。

---

### Phase 3: Blocking 切替（PR #3）

**目的**: default backend を `mcp` に切替、`tmux send-keys` を緊急介入用 fallback に限定。

#### 3.1 切替対象

- `session-comm.sh` 内 default を `TWILL_MSG_BACKEND=${TWILL_MSG_BACKEND:-mcp}` に変更（1 行）
- 既存 `inject` / `inject-file` deprecation alias は維持（Phase 4 で削除）

#### 3.2 bats integration test

`plugins/session/tests/bats/session-comm-mcp-integration.bats`:

- Pilot↔Worker 双方向送信（mailbox jsonl 経由）
- ULID ordering の正しさ（`recv` の since-filter 確認）
- 並列 100 msg 送信で損失ゼロ（AC5-2、stress test）
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` で動作（AC5-3 = AT 非依存性）
- backend 切替（`tmux` / `mcp` 両方）で同テスト PASS（AC5-4）

#### 3.3 Phase 3 完了条件

- bats integration test 全 PASS
- production session で 1 日以上連続稼働、observer/Pilot から問題報告なし
- `mcp-shadow-compare.sh` が削除可能な状態（shadow log は dispose）

---

### Phase 4: Cleanup（PR #4）

**目的**: deprecation alias 削除 + lint 追加 + 関連 Issue close。

#### 4.1 削除対象

- `session-comm.sh::cmd_inject_file`（ファイル全体は維持、関数のみ削除 / shim 化）
- `inject` / `inject-file` deprecation alias
- `mcp-shadow-compare.sh`（migration 完了で不要）
- `_shadow_dispatch` ロジック

#### 4.2 `twl audit` 拡張（lint）

`cli/twl/src/twl/audit/checks.py` または `plugins/twl/scripts/twl-audit-lint.sh` に以下を追加:

```python
# tmux send-keys 直叩き禁止 lint
TMUX_SEND_KEYS_WHITELIST = [
    "plugins/session/scripts/session-comm-backend-tmux.sh",
    "plugins/twl/skills/su-observer/scripts/budget-detect.sh",  # Escape 緊急介入
    # 必要に応じて kill-window 系を追加
]
```

`grep -rn "tmux send-keys" plugins/{twl,session}/{scripts,skills}/` で whitelist 外の hit があれば lint 失敗。

#### 4.3 関連 Issue 処理

- `#1033` close — close rationale: `tools_comm.py` で実現済（ADR-029 Decision 1 案 A の系）
- `#1050` close — Phase 4 で `cmd_inject_file` 削除完了 → flock 競合の対象自体が消滅
- `#1034` epic close — Tier B (`#1032`) merge + 本 Tier 2 Phase 3 完了の AND 条件
- `#1197` 再評価 — subshell mock 設計修正の前提が変わるため、Phase 4 完了時点で必要性を判定

#### 4.4 Phase 4 完了条件

- `twl audit` 経由 lint で whitelist 外の `tmux send-keys` 直叩き 0 件
- 上記 4 Issue の close / 再評価が GitHub 上で完了
- `architecture/migrations/tier-2-caller/` の本ドキュメント + `rollback-plan.md` を `archive/` に移動（Phase 4 cleanup）

---

## 4. Shadow Log 設計

### 4.1 ログ出力先

- **shadow log**: `/tmp/twill-mcp-shadow.log` (host scope, observer 直読み用)
- **mailbox jsonl**: `.twill/state/mailbox/<window>.jsonl` (project scope, `tools_comm.py` 管理)

### 4.2 ログ形式

shadow log は append-only TSV 風 KV 形式:

```
2026-05-03T01:23:45Z cmd=send window=pilot text="continue" primary_rc=0 mcp_dry_run=ok ulid=01HXXX
2026-05-03T01:23:50Z cmd=send-file window=worker-1 file=/tmp/prompt.md primary_rc=0 mcp_dry_run=ok ulid=01HYYY
```

mismatch 検出ロジック:
1. shadow log の各行から `window` + `text` または `file` ハッシュを抽出
2. 対応する mailbox jsonl エントリの `recipient` + `body` ハッシュと突合
3. 不一致 / 欠損があれば mismatch として stdout に JSON 出力

### 4.3 retention

- shadow log は logrotate で 7 日保管 + gzip 圧縮
- mailbox jsonl は ADR-028 atomic write 規約に準拠（delete は Phase 4 完了後の運用判断）

---

## 5. bats Test 設計

### 5.1 Strategy 層 (Phase 1)

`session-comm-strategy.bats`:

```bash
@test "TWILL_MSG_BACKEND=tmux で _tmux_send 呼出" { ... }
@test "TWILL_MSG_BACKEND=mcp で _mcp_send 呼出" { ... }
@test "TWILL_MSG_BACKEND=mcp_with_fallback で shadow log 出力" { ... }
@test "不正値で error exit" { ... }
@test "backend ファイル欠落時 tmux fallback + WARN" { ... }
```

### 5.2 Backend 単体 (Phase 1)

`session-comm-backend-tmux.bats` / `session-comm-backend-mcp.bats`:

- `_tmux_send` の `tmux send-keys` 呼出引数検証（mock tmux）
- `_mcp_send` の `python3 -m twl.mcp_client` 呼出引数検証（mock python）
- error path（tmux 不在、MCP server 接続失敗）

### 5.3 Integration (Phase 3)

`session-comm-mcp-integration.bats`:

- Pilot 1 + Worker 1 で双方向 100 msg、損失 0
- ULID ordering（`recv --since` で過去メッセージ除外）
- AT 非依存性（`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` 環境）
- backend 切替で同テスト PASS

### 5.4 Lint (Phase 4)

`twl-audit-tmux-send-keys.bats`:

- whitelist 内ファイルは PASS
- whitelist 外 hit で lint 失敗
- whitelist 一覧と実装の同期確認

---

## 6. 実装単位とリスク

### 6.1 PR 構成

ADR-029 Decision 5 に従い 3 PR 構成（PR 番号は連番、Phase 番号と必ずしも一致しない）:

- **PR #1**: Phase 1 + Phase 2 を一括（shadow log 並走で blocking なし、Phase 2 観察期間中は同 PR 内で管理。merge 後に shadow 観察を開始）
- **PR #2**: Phase 3 (default 切替、blocking、`#1033`/`#1034` close)
- **PR #3**: Phase 4 (cleanup、lint 追加、`#1050` close)

### 6.2 主要リスクと緩和

| リスク | 緩和 |
|---|---|
| 5 ファイル同時切替で意図しない動作変更 | shadow mode で 1 週間以上 mismatch 0 件確認後 Phase 3 移行 |
| shadow log 解析の人為ミス | `mcp-shadow-compare.sh` で自動検出、observer 日次レポート |
| MCP server 障害時の通信断絶 | `try/except ImportError` gate + `session-comm-backend-tmux.sh` 緊急 fallback 維持 |
| AT 機能依存リスク | bats integration test で `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` 動作を必須化 |
| inject-next-workflow.sh の trace_log 互換性 | 既存 `_trace_log` write を維持（`session_msg send` の wrapper 内で trace 記録） |

### 6.3 effort 見積（ADR-029 = L effort）

| Phase | Worker 想定 | 内訳 |
|---|---|---|
| Phase 1+2 | ~3-4h | Strategy 層 + 2 backend + caller 書換 + bats unit |
| Phase 3 | ~1-2h | default 切替 + bats integration + 観察 |
| Phase 4 | ~1-2h | cleanup + lint + Issue close |
| **Total** | **~6-8h** | ADR-029 §実装単位 と整合 |

---

## 7. Wave 21 実装前チェックリスト

PR #1 起票前に以下を確認:

- [ ] `tools_comm.py` の `_send_msg_impl` / `_recv_msg_impl` が ADR-028 atomic write 規約準拠（既に確認済、ADR-029 §Decision 5 経緯参照）
- [ ] `cli/twl/src/twl/mcp_client/` モジュール設計の事前合意（新規モジュール、Phase 1 で作成）
- [ ] `TWILL_MSG_BACKEND` env var の default policy（`tmux` から `mcp` への移行タイミング）
- [ ] `mcp-shadow-compare.sh` の `#1225 deps-yaml-guard` pattern 再利用妥当性
- [ ] `cld-spawn` / `cld-observe` の挙動への影響評価（capture は対象外、inject-file のみ migration）
- [ ] `pilot-fallback-monitor.sh` の resolve ロジック互換性確認

## 8. 関連参照

- **ADR-029** `decisions/ADR-029-twl-mcp-integration-strategy.md` Decision 5 — 本 migration の上位決定
- **ADR-028** `decisions/ADR-028-atomic-rmw-strategy.md` — mailbox jsonl の atomic write 規約
- **ADR-022** `decisions/ADR-022-chain-ssot-boundary.md` — chain SSoT 影響時の `--deps-integrity` PASS 要件
- **`#1225` deps-yaml-guard** — shadow → blocking 切替 pattern の reference
- **`tools_comm.py`** — `cli/twl/src/twl/mcp_server/tools_comm.py` L66-78, L147-179, L182-207
- **rollback-plan.md** — 同階層、Phase 別 rollback 手順
