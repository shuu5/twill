# Tier 2 Caller Migration Rollback Plan

ADR-029 Decision 5 (2026-05-02 amendment) の補助ドキュメント。`migration-strategy.md` で定義した Phase 1-4 の各段階での rollback 手順、緊急時 1 コマンド復帰手順、データロス対策を明文化する。

**Status**: Planning — Wave 21 実装前承認待ち
**Owner**: Tier 2 caller migration（`#1037` Tier 2 / `#1034` epic）
**Companion**: `migration-strategy.md`（同階層）

---

## 1. Rollback の前提と原則

### 1.1 Rollback トリガー

以下のいずれかが観測されたら即時 rollback を判断する:

- **inject 失敗率 > 5%**: shadow log または production log で `_mcp_send` の error rate が継続的に 5% を超える
- **mailbox jsonl 整合性破壊**: `tools_comm.py` の atomic append 失敗、jsonl パースエラー、ULID 重複
- **AT 非依存性破綻**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` 環境で送信失敗が再現
- **observer / Pilot からの critical 報告**: 通信途絶、wave 進行不能、HUMAN GATE inject 失敗
- **bats integration test の継続的 FAIL**: Phase 3 移行後の継続テストで 2 連続以上の FAIL

### 1.2 Rollback 原則

- **データロスゼロを最優先**: mailbox jsonl は **削除しない**（rollback 後の調査用に保持）
- **段階的復帰**: 1 段階ずつ巻き戻し、各段階で動作確認してから次へ
- **既存 caller への影響最小化**: deprecation alias を最後まで保持し、caller 側コード変更を最小化
- **緊急時は env var 1 つで切替**: `TWILL_MSG_BACKEND=tmux` を export するだけで復帰可能な経路を Phase 3 後も維持

---

## 2. 緊急 rollback（最速復帰）

production session で critical 障害が発生した場合の最速復帰手順。

### 2.1 即時 1 コマンド復帰（Phase 3 後でも可能）

```bash
# 全 production session でこの env var を export するだけで tmux backend に切替
export TWILL_MSG_BACKEND=tmux
```

**作用**:
- `session-comm.sh::session_msg` dispatcher が `_tmux_send` 経由に切替
- `tools_comm.py` への呼出停止、tmux send-keys 経路で送信
- caller 側コードは無変更（API 名 `session_msg send` のまま）
- `session-comm-backend-tmux.sh` が呼出される

**前提条件**:
- Phase 3 後でも `session-comm-backend-tmux.sh` を **削除しない**（Phase 4 の clean up でも保持）
- `_tmux_send` / `_tmux_send_file` 関数が functional な状態を維持

### 2.2 永続化（再起動・新セッション対応）

env var を tmux session 起動 hook に追加:

```bash
# ~/.bashrc または tmux.conf の new-session-hook に追加
export TWILL_MSG_BACKEND=tmux
```

または各 worktree の `.envrc` に追加（direnv 利用時）:

```bash
# .envrc
export TWILL_MSG_BACKEND=tmux
```

### 2.3 影響を受ける Wave 状態

env var 切替時点で:
- **送信中の MCP message**: mailbox jsonl に既に append 済のメッセージは保持、recv 側で読み出し可能
- **未送信の MCP message**: なし（`_mcp_send` は同期呼出、env 切替後の呼出から tmux 経路）
- **Pilot/Worker の inject queue**: tmux send-keys 経路に切替後の inject から有効

---

## 3. Phase 別 rollback 手順

各 Phase の PR が merge された後の rollback 手順。**git revert** または **手動 cleanup** の 2 経路を用意。

### 3.1 Phase 1 + 2 (PR #1) rollback

**シナリオ**: Strategy 層の dispatch ロジック自体に bug、または backend wrapper の根本欠陥。

#### 経路 A: git revert（推奨）

```bash
# main で
git revert <PR_1_MERGE_COMMIT> -m 1
# 必要なら autopilot 経由で実装
gh pr create --title "revert: ADR-029 Decision 5 PR#1 — Tier 2 caller migration" \
  --body "Rollback rationale: <REASON>。詳細は rollback-plan.md §3.1 参照"
```

**revert で復元される状態**:
- `session-comm.sh` の `cmd_inject` / `cmd_inject_file` 直叩き呼出
- caller 側の `inject` / `inject-file` 直接呼出
- `session-comm-backend-{tmux,mcp}.sh` の削除
- `mcp-shadow-compare.sh` の削除

#### 経路 B: 手動 cleanup（git revert 不可時）

1. **env override で即時無効化**: `export TWILL_MSG_BACKEND=tmux`
2. **PR #1 の修正 PR**: `session-comm.sh` の dispatcher を `inject` / `inject-file` 直接呼出に書き換え + backend ファイル削除
3. **caller 側は維持可**（`session_msg send` API は alias として `inject` を呼ぶ shim を残す）

### 3.2 Phase 3 (PR #2) rollback

**シナリオ**: default `mcp` 切替後に inject 失敗率上昇 / mailbox 整合性問題 / AT 依存性問題。

#### 経路 A: env var で即時切替（最速、推奨）

```bash
export TWILL_MSG_BACKEND=tmux
# 全 production session で適用
```

→ **§2.1 緊急 rollback** と同等。コード変更不要。

#### 経路 B: PR #2 git revert

```bash
git revert <PR_2_MERGE_COMMIT> -m 1
```

**revert で復元される状態**:
- `session-comm.sh` の default backend `tmux`
- 既存 `inject` / `inject-file` API 経路を default として使用

### 3.3 Phase 4 (PR #3) rollback

**シナリオ**: lint 追加または cleanup で既存 caller / 緊急介入が壊れた。

#### 経路 A: lint 緊急 disable

`twl audit` の `tmux send-keys` lint を whitelist 拡張または環境変数で無効化:

```bash
export TWILL_AUDIT_SKIP_TMUX_SEND_KEYS=1
```

#### 経路 B: PR #3 git revert

```bash
git revert <PR_3_MERGE_COMMIT> -m 1
```

**revert で復元される状態**:
- `cmd_inject_file` の関数本体復元
- `inject` / `inject-file` deprecation alias 復元
- `mcp-shadow-compare.sh` 復元
- `_shadow_dispatch` ロジック復元
- `tmux send-keys` 直叩き lint 無効化

---

## 4. データロス対策

### 4.1 mailbox jsonl の保護

**Rollback 中も mailbox jsonl は削除しない**。理由:

- 送信済 MCP message の調査用（rollback 原因解析）
- ULID ordering の検証（mismatch があれば原因特定）
- `tools_comm.py` の atomic append 規約により、ファイル破壊リスク低い

### 4.2 shadow log の retention

- Phase 2 で生成した `/tmp/twill-mcp-shadow.log` は **rollback 後 30 日保持**
- mismatch 解析を含む postmortem の根拠資料

### 4.3 trace log の互換性

`inject-next-workflow.sh` の `_trace_log` write は **rollback 中も維持**:

- 既存 trace log 形式 `[timestamp] issue=N skill=X result=ok|error reason="..."` を Phase 1 改修後も保持
- rollback 時は `_tmux_send` 経路で同じ trace log に書込
- 既存 observer/Pilot の trace 解析ツールへの影響ゼロ

### 4.4 backup ポイント

各 Phase merge 前に以下を `.twill/backups/<phase>/` に保存（手動運用、または su-observer 自動化）:

- `session-comm.sh` 全文
- `mailbox/<window>.jsonl` snapshot（直前 24h）
- `bats` test 結果ログ

---

## 5. settings.json mcp_tool 削除手順（緊急時）

`tools_comm.py` 経由の MCP tool 自体を緊急停止する場合（mailbox jsonl 破壊時など）。

### 5.1 settings.json での無効化

`~/.claude/settings.json` または project-local `.claude/settings.json` から `twl` MCP server エントリを一時削除:

```json
{
  "mcpServers": {
    "twl": {  // ← この block をコメントアウトまたは削除
      "command": "python",
      "args": ["-m", "twl.mcp_server.server"]
    }
  }
}
```

### 5.2 影響範囲

- `mcp__twl__twl_send_msg` / `twl_recv_msg` / `twl_notify_supervisor` が利用不可に
- Phase 3 後は **必ず `TWILL_MSG_BACKEND=tmux` への切替が必要**（MCP backend が呼出失敗で fallback 経路に依存）
- 既存 5 tool (`twl_validate` / `twl_audit` / `twl_check` / `twl_state_read` / `twl_state_write`) も同時に無効化される副作用に注意

### 5.3 復帰

mailbox 整合性確認後、settings.json を復元 + Claude Code セッション再起動:

```bash
# Claude Code を一旦終了
# settings.json を復元
# 新しいセッションで MCP server が再接続
```

---

## 6. session-comm-backend-tmux.sh restore 手順

Phase 1 で `cmd_inject` / `cmd_inject_file` を移動した先 (`session-comm-backend-tmux.sh`) が損傷した場合の復元手順。

### 6.1 復元元

- **git history**: PR #1 merge commit 直前の `session-comm.sh` 全文
- **backup**: `.twill/backups/phase-1/session-comm.sh`（推奨運用）

### 6.2 復元手順

```bash
# 1. git history から取得
git show <PR_1_PARENT_COMMIT>:plugins/session/scripts/session-comm.sh > /tmp/session-comm-pre-phase1.sh

# 2. 該当関数 (cmd_inject / cmd_inject_file) 部分を抽出
sed -n '/^cmd_inject() {/,/^}/p' /tmp/session-comm-pre-phase1.sh > /tmp/cmd_inject.sh
sed -n '/^cmd_inject_file() {/,/^}/p' /tmp/session-comm-pre-phase1.sh > /tmp/cmd_inject_file.sh

# 3. session-comm-backend-tmux.sh に追記または上書き
cat /tmp/cmd_inject.sh /tmp/cmd_inject_file.sh > plugins/session/scripts/session-comm-backend-tmux.sh
# 関数名を _tmux_send / _tmux_send_file にリネーム（手動）

# 4. 動作確認
bash -n plugins/session/scripts/session-comm-backend-tmux.sh
TWILL_MSG_BACKEND=tmux session-comm.sh send <test-window> "test message"
```

---

## 7. Rollback 完了後の post-mortem

各 rollback 実施後、以下を `.controller-issue/<ts>/postmortem-rollback.md` に記録:

1. **発生事象の詳細**: 観測された症状、再現手順、影響範囲
2. **rollback 経路**: 採用した経路（A/B）、所要時間
3. **データロス有無**: mailbox jsonl / shadow log の整合性確認結果
4. **根本原因仮説**: shadow log + bats test 結果からの推測
5. **再発防止策**: 修正 PR の方針、追加 test の必要性
6. **関連 Issue**: rollback 起因の新規 Issue 起票（co-issue 経由）

postmortem テンプレートは `plugins/twl/architecture/decisions/ADR-029` の next amendment で正式化を検討。

---

## 8. 緊急連絡先（運用）

- **observer (su-observer)**: tmux window `su-observer` で常駐、Discord DM (chat_id=1486902538123870319, memory `reference_discord_dm`) で通知可能
- **Pilot session**: `autopilot` window で実行中、kill する場合は `tmux send-keys -t autopilot Escape` で interrupt
- **MCP server プロセス**: `pgrep -f "twl.mcp_server"` で検出、`kill -TERM <PID>` で停止可能

---

## 9. 関連参照

- **migration-strategy.md** — 同階層、Phase 別実装計画の詳細
- **ADR-029** `decisions/ADR-029-twl-mcp-integration-strategy.md` Decision 5 — 上位決定
- **ADR-028** `decisions/ADR-028-atomic-rmw-strategy.md` — mailbox jsonl atomic write 規約
- **`tools_comm.py`** — `cli/twl/src/twl/mcp_server/tools_comm.py`（rollback 対象外、mailbox 実装本体）
- **memory `feedback_inject_queue_verification`** — inject 失敗の検証 pattern（rollback トリガー判定の参考）
- **memory `feedback_session_budget_stop`** — orchestrator kill 手順（緊急介入時の参考）
