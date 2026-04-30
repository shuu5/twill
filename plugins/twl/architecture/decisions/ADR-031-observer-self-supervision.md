# ADR-031: Observer Self-Supervision — cld-observe-any 自律再起動機構

## Status

Accepted

## Context

2026-04-30 09:00 頃、ThinkPad の Claude session が予期せず crash し、`cld-observe-any`（Worker pane 監視 daemon）が同時に死亡した。observer 復帰後、`cld-observe-any` は動作しておらず、observer LLM が手動で起動コマンドを発行するまで自律監視機能が断絶していた。

### 死亡メカニズム（AC0 検証結果）

コード解析 + 2026-04-30 インシデントにより以下を確認した:

1. `cld-observe-any` は `trap ... INT TERM` で SIGINT/SIGTERM を捕捉するが **SIGHUP は未 trap**
2. Claude Code の `Bash run_in_background` で起動した子プロセスは非インタラクティブ bash 配下のため、POSIX 標準の「親 shell 終了時 SIGHUP 伝播」は通常成立しない
3. **最有力仮説**: tmux pane kill（tmux `pane-died` hook の副作用）または Claude Code プロセス終了時の明示的な子プロセス group SIGTERM により死亡
4. **実証結論**: 死亡メカニズムの詳細に関わらず、observer crash 後の resume 時に `cld-observe-any` が停止していることが実証された

詳細な再現実験結果は `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md` §11.5 を参照。

### 設計選択肢の評価

| 案 | 概要 | W1(P1解決,重み3) | W2(portability,重み2) | W3(実装コスト,重み2) | W4(既存整合,重み1) | スコア |
|---|---|---|---|---|---|---|
| **A: systemd daemon** | systemd user unit + loginctl enable-linger で完全 detach | 5 | 1 | 2 | 3 | 24 |
| **B: SessionStart hook + launcher** | SessionStart hook で pgrep 確認 → 不在なら flock+nohup 起動 | 3 | 4 | 4 | 5 | **30** |
| **C': pipe-pane + named pipe** | tmux pipe-pane で准 event-driven 検知 | 4 | 2 | 1 | 2 | 17 |
| **D: in-process self-restart** | observer SKILL.md Phase 0 で pgrep → 不在なら nohup | 2 | 5 | 5 | 5 | 28 |

**重み付き評価基準:**
- W1 (P1 解決完全度, 重み 3): crash 後 gap がない（再起動遅延 ≤ 60s）
- W2 (portability, 重み 2): host 固有設定の少なさ
- W3 (実装/保守コスト, 重み 2): bats test 含む変更量
- W4 (既存機構との整合, 重み 1): 既存 pgrep/flock 実装の再利用度

## Decision

**Option B を採択する**（スコア 30、最高）。

### 採択理由

- W1 で Option A (score 5) に劣るが (score 3)、SessionStart hook の resume 遅延は ≤ 60s の許容範囲内
- W2/W3/W4 で Option A に大きく勝る（host-level systemd 不要、既存 flock/pgrep パターン再利用）
- Option D は observer 自身が crash している状態で Phase 0 が実行されないため P1 を解決できない根本的欠陥がある

### Option C 撤回理由

当初の `pane-content-changed` hook は tmux 公式 hook 一覧 (`man tmux` HOOKS section) に存在しない。`pipe-pane` + named pipe 案 (C') に修正したが、W3=1 (実装コスト最大) かつ W2=2 で劣るため除外。

### Option D 除外理由

observer LLM 自身が crash した状態では Phase 0 が実行されない。SessionStart hook なら observer crash 後の resume でも自動発火するため Option B が優位。

### Option A の考慮事項（将来の参考）

現ホスト ThinkPad では `loginctl show-user $USER | grep Linger` → `Linger=no`。Option A 採択時は `sudo loginctl enable-linger $USER` が必要。CI への適用も複雑になる。

## Implementation

### 実装対象

1. `plugins/session/scripts/cld-observe-any-launcher` — flock + nohup による launcher script
2. `.supervisor/session.json` schema に `cld_observe_any: { pid, started_at, log_path }` フィールド追加
3. `~/.claude/settings.json` (host dotfiles) への SessionStart hook 追加は **本 PR スコープ外** — host 側 dotfiles リポジトリで別途実施

### SessionStart hook 設定例（host dotfiles 側で実施）

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "pgrep -f 'cld-observe-any$' >/dev/null 2>&1 || bash /path/to/plugins/session/scripts/cld-observe-any-launcher [OPTIONS]"
          }
        ]
      }
    ]
  }
}
```

### Launcher の動作

1. `flock -n 9` で多重起動防止（SessionStart hook の並列発火対策）
2. `pgrep -f cld-observe-any$` で既存 daemon 確認
3. 不在かつ session.json に前回 PID あり → `daemon-down-<ts>.json` event 出力
4. `nohup cld-observe-any [args] >> /tmp/cld-observe-any.log 2>&1 &` で起動
5. 1 秒後生存確認 → 失敗時は `daemon-startup-failed-<ts>.json` event 出力
6. `.supervisor/session.json` の `cld_observe_any` フィールドを更新

## Boundary

本 ADR は `observer self-supervision` というドメインを確立する:

- **observer lifecycle** (Claude Code session 管理) と **daemon lifecycle** (cld-observe-any プロセス) の明確な分離
- daemon の再起動責務は SessionStart hook（observer 外部の Claude Code フレームワーク）に委譲
- observer SKILL.md は引き続き `check_monitor_cld_observe_alive()` で daemon 生存を確認し、不在時に SessionStart hook 設定の確認を促す（P1 解決の補完）

## Consequences

### Positive

- observer crash → resume 後 ≤ 60s 以内に cld-observe-any が自動再起動する
- flock による多重起動防止で並列 hook 発火でも安全
- host-level 設定（systemd）不要で portability が高い
- 既存 `pgrep -f cld-observe-any`（`observer-parallel-check.sh:135-150`）と整合

### Negative / Risks

- SessionStart hook のトリガー頻度が多い環境では startup lag が積み重なる可能性
- `cld-observe-any` に `--window`/`--pattern` 引数が必須のため、hook 設定時に引数を正しく渡す必要がある（#1147 で指摘済みの既存バグ）

## Relations

- **supersedes**: なし
- **relates to**: ADR-014 (Supervisor redesign) — Supervision Context の boundary を補強
- **closes**: Issue #1147 (option B のサブセットとして本 PR で統合実施)
- **pitfalls**: `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md` §11.5
