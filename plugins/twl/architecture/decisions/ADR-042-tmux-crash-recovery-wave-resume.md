# ADR-042: tmux server crash recovery + wave resume 統合設計

**Status**: Accepted
**Date**: 2026-05-11
**Issue**: #1360
**Related**: ADR-014 (supervisor redesign), ADR-034 (autonomous chain reliability)

---

## Context

Issue #1360 で 2 件の tmux server crash incident が 2026-05-03 (16:17 / 21:33 JST) に発生し、全 observer / Pilot / Worker tmux session が消失。Wave 進行が中断された。`tmux-protect-server.sh` による systemd user scope 配下化 (hash 4ac8e10d、90855a48) は SSH 切断由来の cgroup 巻き添えは防ぐが、**tmux server プロセス自身の異常終了は捕捉できない**。

### 観測した failure mode

| 時刻 | 状況 | 影響 |
|---|---|---|
| 2026-05-03 16:17 JST | Wave 33 PR #1350 merge 直後の cleanup | observer + ap-w33 + Worker 全消失、4h22m blackout |
| 2026-05-03 21:33 JST | Wave 34 PR #1359 merge 直後の cleanup | observer + ap-w34 + Worker 全消失、7 分 blackout |

両 incident の共通点: **PR merge 後の連続 `tmux kill-window` 操作**。`safe_kill_window` ヘルパーが集中化されたが (Issue #1385)、sleep なしで burst kill すると server の SIGSEGV を誘発する可能性がある。

### 既存対策との関係

- `tmux-protect-server.sh` (hash 4ac8e10d): user scope 化により SSH 切断の巻き添えを防ぐ
- `tmux-safety-guard.sh` (新規, Issue #1360 AC-3c): `tmux kill-window` 直接呼び出し禁止 lint
- ADR-014 (supervisor redesign): su-observer メタ認知レイヤー
- ADR-034 (autonomous chain reliability): wave-queue.json + auto-next-spawn の連鎖

### scope 制限 (Issue #1360 内)

本 ADR は **設計の枠組みを確定する** ところまでを範囲とする。実装は以下の境界:

- **本 PR (Wave U.audit-fix)**: `safe_kill_window` 内 `sleep 1` 挿入、`tmux-safety-guard.sh` lint、3 件の runbook 整備、wave-queue schema 拡張
- **Wave 35 以降 (別 Issue)**: `tmux-twill.service` の systemd unit file 整備、`tmux-resurrect` 統合、wave resume hook 実装

## Decision

### D-1: tmux-twill.service の役割（HUMAN GATE 実装）

tmux server crash 自動 recovery のため、以下の systemd user unit を ipatho-server-2 / thinkpad で導入する。本 ADR は **設計仕様のみ確定し、unit file 自体は host 側で手動配置** する（systemd 設定変更には sudo 不要だが `systemctl --user enable` 等の host コマンド実行が必要なため）。

```ini
# ~/.config/systemd/user/tmux-twill.service
[Unit]
Description=tmux server (twill autopilot)
After=default.target

[Service]
Type=forking
ExecStart=/usr/bin/tmux new-session -d -s twill-ipatho2 -c /home/shuu5/projects/local-projects/twill/main
ExecStartPost=/bin/bash -c '/home/shuu5/.config/systemd/user/tmux-twill-poststart.sh || true'
Restart=on-failure
RestartSec=15
KillMode=process

[Install]
WantedBy=default.target
```

> ★HUMAN GATE: `systemctl --user enable tmux-twill.service` をユーザが実行する

`ExecStartPost` は本 ADR D-2 の resume hook を起動する。

### D-2: wave resume hook 設計

`tmux-twill.service` 起動時 (= server crash 後の自動 spawn 時) に `wave-queue.json` を読み、resume 対象 Wave を検出する。

#### 検出ロジック

```bash
# tmux-twill-poststart.sh (擬似コード)
WAVE_QUEUE="${SUPERVISOR_DIR}/wave-queue.json"

if [[ ! -f "$WAVE_QUEUE" ]]; then
  exit 0  # no queue → cold start
fi

# in_progress_issues フィールドを読む（D-3 で schema 拡張）
RESUME=$(jq -r '.queue[] | select(.in_progress_issues // [] | length > 0)
                | "\(.wave) \(.in_progress_issues | join(","))"' "$WAVE_QUEUE")

if [[ -n "$RESUME" ]]; then
  # observer 自動 spawn + resume hint 渡し
  tmux new-window -n observer -d \
    "cld --continue --hint 'resume wave $RESUME (auto recovery after tmux crash)'"
fi
```

> 重要: 本実装は本 PR では行わない (Wave 35 で別 Issue 起票)。本 ADR は仕様を確定するのみ。

### D-3: wave-queue.schema.json 拡張

resume 対象 Issue を保持できるよう、`WaveEntry` に optional フィールドを追加する。

```json
{
  "definitions": {
    "WaveEntry": {
      "required": ["wave", "issues", "spawn_cmd_argv", "depends_on_waves", "spawn_when"],
      "additionalProperties": false,
      "properties": {
        "wave": {"type": "integer", "minimum": 1},
        "issues": {"type": "array", "items": {"type": "integer"}},
        "in_progress_issues": {
          "type": "array",
          "items": {"type": "integer"},
          "description": "resume target Issues — tmux crash 後の recovery hook で参照（D-2）"
        },
        "spawn_cmd_argv": {"type": "array", "items": {"type": "string"}, "minItems": 1},
        "depends_on_waves": {"type": "array", "items": {"type": "integer"}},
        "spawn_when": {"type": "string", "enum": ["all_current_wave_idle_completed"]}
      }
    }
  }
}
```

**互換性**: 既存エントリは `in_progress_issues` / `resume_issues` を持たないが、optional 扱いなので validation pass。`auto-next-spawn.sh` の inline jq バリデーションは `spawn_when == "all_current_wave_idle_completed"` のみを検証しているため、新フィールドを無視する (deduced from agent exploration)。**AC-6c (AUTO_NEXT_SPAWN=0 path) は影響を受けない**。

### D-4: tmux-resurrect 統合戦略

既存の `tmux-resurrect-save.service` (ユーザ設定済) と Claude Code session restore の連携:

- pane → session_id のマッピングは `plugins/session/scripts/claude-session-save.sh` が `~/.local/state/claude/tmux-pane-map.tsv` に既保存
- tmux-twill.service の `ExecStartPost` で `tmux-resurrect restore` を fire し、各 pane で `cld --continue` を再起動する
- worktree が削除済みの Worker session は restore せず skip (cwd 不在のため `cld --continue` が cold start に fallback する)

> 設計詳細・実装は Wave 35 で別 Issue 化（本 ADR の scope 外）

### D-5: 段階的実装ロードマップ

| Phase | 内容 | 担当 PR / Issue |
|---|---|---|
| **本 PR** | safe_kill_window sleep, lint, runbook, schema 拡張, 本 ADR | #1360 follow-up (Wave U.audit-fix) |
| Wave 35-A | tmux-twill.service unit file commit (`config/`) + install runbook | 別 Issue |
| Wave 35-B | tmux-twill-poststart.sh wave resume hook 実装 | 別 Issue |
| Wave 35-C | tmux-resurrect-save.service 連携 (cld --continue) | 別 Issue |
| Wave 35-D | bats regression: kill-server → service spawn → resurrect restore | 別 Issue |

## Non-goal

- tmux 本体への patch 投稿
- kernel-level cgroup 制御の変更
- tmux-resurrect 以外の session restore 機構の評価
- 本 PR で systemd unit file を commit すること（host 環境差異が大きいため runbook 経由で配布）

## Consequences

### Positive

- tmux burst-kill による server crash 発生確率が低下（`safe_kill_window` 内 `sleep 1`）
- crash 発生時の root cause 分析が可能（coredump + strace runbook）
- wave-queue schema が resume 対象 Issue を保持できるよう拡張済み（Wave 35 実装の前提条件 D-3）
- 3 runbook + 本 ADR で recovery 全体像が文書化される

### Negative

- `safe_kill_window` 呼び出しあたり 1 秒の overhead（19 caller × 1秒 = 最大 19 秒のバッチ cleanup 増加）
- tmux-twill.service の実装は Wave 35 まで遅延（本 PR では設計のみ）
- HUMAN GATE が複数残る（systemctl --user enable, sudo systemd-coredump 設定, thinkpad tmux -V 確認）

### Risks

- `sleep 1` が短すぎて burst-kill 対策として不十分な可能性 → revisit trigger は [tmux-version-evaluation.md](../runbooks/tmux-version-evaluation.md) § 据え置きの条件
- `SAFE_KILL_WINDOW_SLEEP=0` 設定が誤って production session で使われると元の failure mode 再発 → bats test で default=1 を保証

## Alternatives Rejected

- **`safe_kill_window` 呼び出し元 19 箇所すべてに `sleep 1` 挿入**: 重複・忘れリスク・コード散漫
- **新 systemd timer での poll-based health check**: too eager / overhead 大
- **ADR-034 への追記のみ**: scope が autonomous chain reliability と異なるため独立 ADR が適切

## 関連 Resource

- Issue: [#1360](https://github.com/shuu5/twill/issues/1360) (P0 incident)
- Runbooks:
  - [coredump-config.md](../runbooks/coredump-config.md)
  - [tmux-strace-runbook.md](../runbooks/tmux-strace-runbook.md)
  - [tmux-version-evaluation.md](../runbooks/tmux-version-evaluation.md)
- Schema: `skills/su-observer/schemas/wave-queue.schema.json` (D-3 で拡張)
- Helper: `scripts/lib/tmux-window-kill.sh` (D-1 で `sleep 1` 挿入)
- Lint: `scripts/tmux-safety-guard.sh` (新規)
