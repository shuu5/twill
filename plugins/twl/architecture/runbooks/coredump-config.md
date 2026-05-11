# Runbook: tmux server coredump 取得設定

**Issue**: #1360 (P0 incident: tmux server protected scope crash)
**Status**: Active
**Date**: 2026-05-11
**HUMAN GATE**: `sudo` 必須のため、本 runbook の手順実行はユーザ責務

---

## 目的

tmux server が `tmux-server.scope` (systemd user scope) 配下で SIGSEGV 等の異常終了を起こした際、coredump を取得して root cause を分析できるようにする。Issue #1360 で 2 件発生した crash incident (2026-05-03 16:17 JST / 21:33 JST) は systemd の scope unregister 報告のみで原因が特定できなかった。

## 前提

- ホスト: Ubuntu Linux 24.04 (systemd-coredump 利用可能)
- 影響範囲: ipatho-server-2 / thinkpad
- tmux server は `~/.config/systemd/user/tmux-twill.service` の `tmux-server.scope` 配下で動作 (Issue #1360 AC-4 で別途整備予定)

## 手順

### Step 1: systemd-coredump パッケージ確認

```bash
dpkg -l | grep systemd-coredump
# 期待: 'ii  systemd-coredump' が表示される
# 未インストールの場合:
sudo apt-get install -y systemd-coredump
```

### Step 2: coredump 保存先設定

`/etc/systemd/coredump.conf` を編集して `Storage=external` (圧縮ファイル形式) を確実にする。

```bash
sudo cp /etc/systemd/coredump.conf /etc/systemd/coredump.conf.bak.$(date +%Y%m%d)
sudo tee /etc/systemd/coredump.conf <<'EOF'
[Coredump]
Storage=external
Compress=yes
ProcessSizeMax=8G
ExternalSizeMax=8G
KeepFree=30G
MaxUse=10G
EOF
```

### Step 3: 設定反映

```bash
sudo systemctl daemon-reexec
# 即時反映確認:
systemd-analyze cat-config systemd/coredump.conf | grep Storage
# 期待: 'Storage=external'
```

### Step 4: tmux server の coredump 取得テスト（オプション）

> ⚠️ **DESTRUCTIVE**: テスト socket で実行すること。default socket では実 session が消える。

```bash
# テスト socket で tmux 起動
tmux -S /tmp/tmux-coredump-test new-session -d -s test
TEST_PID=$(pgrep -f 'tmux -S /tmp/tmux-coredump-test')
sudo kill -SIGSEGV "$TEST_PID"
# coredumpctl で確認 (5-10秒待機)
sleep 5
coredumpctl list | tail -3
# 期待: tmux プロセスの coredump が記録されている
```

### Step 5: 実 incident 時の analysis 手順

```bash
# 最新の tmux coredump を取得
coredumpctl list tmux | tail -5
# 特定 PID の core を gdb で開く
coredumpctl gdb <PID>
# gdb 内:
(gdb) bt full           # full backtrace
(gdb) info threads      # スレッド一覧
(gdb) thread apply all bt   # 全スレッド bt
```

## 関連 incident

| 日時 | 状況 | tmux PID |
|---|---|---|
| 2026-05-03 16:17 JST | Wave 33 (#1310 P0) PR #1350 merge 直後の cleanup | 不明 (coredump 未取得) |
| 2026-05-03 21:33 JST | Wave 34 (#1302) PR #1359 merge 直後の cleanup | 不明 (coredump 未取得) |

両 incident とも coredump 未取得のため、本 runbook 適用後の次回 crash 時に初めて root cause 分析が可能になる。

## 検証チェックリスト

- [ ] `dpkg -l | grep systemd-coredump` で installed
- [ ] `cat /etc/systemd/coredump.conf | grep Storage` で `Storage=external`
- [ ] `coredumpctl list` でテスト coredump が登録されている (Step 4 実行時)
- [ ] `/var/lib/systemd/coredump/` のディスク使用量が `KeepFree=30G` を侵食しない
- [ ] ★HUMAN GATE: ユーザが ipatho-server-2 で本 runbook を実行済み

## 関連 ADR

- [ADR-042](../decisions/ADR-042-tmux-crash-recovery-wave-resume.md) — tmux crash recovery + wave resume 統合設計
