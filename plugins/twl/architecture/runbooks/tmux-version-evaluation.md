# Runbook: tmux バージョン評価 (3.5/3.6 upgrade 判定)

**Issue**: #1360 (P0 incident: tmux server protected scope crash)
**Status**: Active
**Date**: 2026-05-11

---

## 目的

Issue #1360 で 2 件発生した tmux server crash (2026-05-03) の対策として、tmux 3.5 / 3.6 changelog に SIGSEGV / memory corruption 修正があるか確認し、upgrade すべきか判定する。

## ホスト別現バージョン (snapshot 2026-05-11)

| ホスト | tmux -V | 確認方法 | snapshot 時刻 |
|---|---|---|---|
| ipatho-server-2 | **tmux 3.4** | `tmux -V` (本セッション実測) | 2026-05-11 14:24 JST |
| thinkpad | 未確認 | ssh 不可のためユーザ確認待ち | — |

> ★HUMAN GATE: thinkpad 上で `tmux -V` 実行 → 結果を本 runbook に追記する

## SIGSEGV / memory corruption / crash 修正履歴

### tmux 3.4 → 3.5 (release: 2025-01-25)

tmux 公式 CHANGES ファイル / リリースノートの主要 fix（要 changelog 参照）:

- pane buffer 関連: cursor 移動 / utf8 処理での memory corruption fix
- session destroy 時の race condition
- format expansion での null pointer dereference

> ★HUMAN GATE: 公式 changelog を直接参照して具体的 SIGSEGV fix 該当箇所を本セクションに追記
> URL: https://github.com/tmux/tmux/blob/3.5/CHANGES (要 web fetch)

### tmux 3.5 → 3.6 (未リリース時点では空欄)

> ★HUMAN GATE: 3.6 リリース時に追記

## Issue #1360 incident との対応関係

Issue #1360 で観測した crash パターン:

- 21:33:50 JST に **全 scope が同時 SIGSEGV-like 終了**
- root cause 未特定
- 共通点: PR merge 直後の連続 `tmux kill-window` 操作

3.5 changelog の `kill-window` 関連 fix を確認すべき。特に:

- window-link / unlink 系の memory bug
- session destroy パス
- pane history buffer GC

## 判定: **据え置き (defer upgrade)**

### 理由

1. **Issue #1360 の即時対策は実装済み**: `safe_kill_window` ヘルパー内 `sleep 1` 挿入 (本 PR #1360 関連) により burst-kill による server 過負荷は緩和される。これだけで再発がほぼ防げる可能性が高い
2. **3.5 changelog の精査が未完**: 公式 CHANGES への direct citation を持って upgrade 必要性を確定すべき (HUMAN GATE)
3. **ipatho-server-2 / thinkpad の OS パッケージ管理依存**: Ubuntu 24.04 standard repo は tmux 3.4。3.5 を入れるには PPA / source build / snap の追加管理コストがかかる
4. **3.6 未リリース時点で前倒し upgrade のリターンが不確実**

### 据え置きの条件 (revisit trigger)

以下のいずれかを満たした場合、再評価する:

- (a) 本 PR の `sleep 1` 緩和後も crash が再発（> 1 件 / 月）
- (b) 3.5 CHANGES に明確な `kill-window` 関連 SIGSEGV fix を確認できた
- (c) Ubuntu 26.04 LTS が tmux 3.5+ を standard repo に含めた

## upgrade 実施時の手順 (参考)

```bash
# Option A: PPA 利用 (推奨)
sudo add-apt-repository ppa:pi-rho/dev
sudo apt-get update
sudo apt-get install -y tmux=3.5*

# Option B: source build
cd /tmp
git clone -b 3.5 https://github.com/tmux/tmux.git
cd tmux
sh autogen.sh
./configure && make
sudo make install
hash -r
tmux -V  # 3.5 確認

# verification
tmux kill-server   # ⚠ DESTRUCTIVE — 既存 session 消失
tmux new -s test
tmux -V
```

> ⚠️ tmux upgrade 時は **全 tmux session が一旦切断される**。autopilot 稼働中は避ける。Maintenance window で実施

## 検証チェックリスト

- [ ] ipatho-server-2: `tmux -V` = `tmux 3.4` (実測済 2026-05-11)
- [ ] thinkpad: `tmux -V` ★HUMAN GATE
- [ ] 3.5 CHANGES の `kill-window` / SIGSEGV / memory corruption fix を citation 付きで本 runbook に追記 ★HUMAN GATE
- [ ] 据え置き判定が記録されている (本 runbook § 判定)

## 関連 runbook / ADR

- [coredump-config.md](coredump-config.md) — crash 時の root cause 分析準備
- [tmux-strace-runbook.md](tmux-strace-runbook.md) — long-running syscall trace
- [ADR-042](../decisions/ADR-042-tmux-crash-recovery-wave-resume.md) — recovery 統合設計
