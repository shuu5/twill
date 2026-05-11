# Runbook: tmux server long-running strace 取得

**Issue**: #1360 (P0 incident: tmux server protected scope crash)
**Status**: Active
**Date**: 2026-05-11
**HUMAN GATE**: `sudo` 必須

---

## 目的

coredump 取得 (`coredump-config.md`) と並行して、tmux server の syscall trace を `strace -f -p <tmux-server-pid>` で long-running 取得し、crash 直前の syscall を分析する。Issue #1360 仮説検証用:

- 仮説 1: tmux 3.4 internal SIGSEGV / memory corruption
- 仮説 2: child scope (tmux-spawn-*.scope) 異常終了の巻き添え
- 仮説 3: pane buffer overflow による memory corruption

## 前提

- `strace` パッケージ installed (`dpkg -l | grep strace`)
- tmux server が `tmux-server.scope` (systemd user scope) で動作中
- `/var/log/tmux-trace.log` 用の書き込み権限 (root or syslog グループ)

## 手順

### Step 1: tmux server PID 取得

```bash
# tmux server プロセスを特定
TMUX_PID=$(pgrep -f '^tmux ' -o)
# 確認
ps -p "$TMUX_PID" -o pid,cgroup,cmd
# 期待: cgroup に tmux-server.scope が含まれる
```

### Step 2: strace 起動 (long-running)

```bash
# 出力ファイル準備（log rotation 対応）
sudo install -d -m 0755 /var/log/tmux-strace
sudo touch /var/log/tmux-strace/tmux-trace.log
sudo chmod 0644 /var/log/tmux-strace/tmux-trace.log

# long-running strace（fork follow + signal trace + ファイルサイズ rotation）
sudo strace -f -tt -e trace=all -e signal=all \
  -o /var/log/tmux-strace/tmux-trace.log \
  -p "$TMUX_PID" &
echo $! | sudo tee /var/run/tmux-strace.pid
```

### Step 3: Log rotation 設定

`/etc/logrotate.d/tmux-strace`:

```
/var/log/tmux-strace/tmux-trace.log {
    daily
    size 1G
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        # strace PID に SIGUSR1 を送って新 file に切替 (strace は再起動不要だが、
        # 強制的に新 fd を開きたい場合は kill -SIGTERM + 再起動)
        if [ -f /var/run/tmux-strace.pid ]; then
            kill -SIGTERM "$(cat /var/run/tmux-strace.pid)" 2>/dev/null || true
        fi
    endscript
}
```

```bash
sudo logrotate -f /etc/logrotate.d/tmux-strace
ls -lh /var/log/tmux-strace/
```

### Step 4: Crash 検知 / 自動停止

```bash
# tmux server が死亡した瞬間 strace も exit する。
# 検知後、最後の 1000 行を別途保存:
if ! kill -0 "$TMUX_PID" 2>/dev/null; then
  cp /var/log/tmux-strace/tmux-trace.log \
     "/var/log/tmux-strace/crash-$(date +%Y%m%d-%H%M%S).log"
  echo "[strace-runbook] tmux server 死亡を検知。crash log を保存しました"
fi
```

### Step 5: 分析

```bash
# 最新 crash log から SIGSEGV / SIGBUS / abort を抽出
sudo grep -E 'SIGSEGV|SIGBUS|abort|--- SIG' /var/log/tmux-strace/crash-*.log | tail -50

# fork / clone / exit シーケンス確認（仮説 2 検証）
sudo awk '/^[0-9]+\s+.*(clone|fork|exit_group|wait4)/' /var/log/tmux-strace/crash-*.log | tail -100

# pane buffer 関連 write/read 確認（仮説 3 検証）
sudo grep -E 'write\(.*[0-9]{4,}' /var/log/tmux-strace/crash-*.log | wc -l
# 期待: 通常 < 1000 / 異常 > 10000
```

## 検証チェックリスト

- [ ] `strace -f -p <pid>` が long-running で動作している
- [ ] `/var/log/tmux-strace/tmux-trace.log` が 1GiB を超えても rotate される
- [ ] crash 発生時に SIGSEGV 等が log に記録される
- [ ] CPU 負荷が許容範囲（strace で 5-10% 程度のオーバーヘッド想定）
- [ ] ★HUMAN GATE: ユーザが ipatho-server-2 で strace 監視を起動

## 注意事項

- strace は **performance overhead** がある。本番運用 (autopilot 稼働中) で常時起動するのは推奨されない。**incident 再発が予想される期間のみ** 限定的に起動する
- syscall trace の disk consumption は典型的に 100MB/hour 程度。log rotation を必ず設定する
- `sudo` 必要なため、本 runbook の自動化は不可。手動運用前提

## 関連 runbook / ADR

- [coredump-config.md](coredump-config.md) — coredump 取得設定（併用推奨）
- [tmux-version-evaluation.md](tmux-version-evaluation.md) — tmux upgrade 判定
- [ADR-042](../decisions/ADR-042-tmux-crash-recovery-wave-resume.md) — recovery 統合設計
