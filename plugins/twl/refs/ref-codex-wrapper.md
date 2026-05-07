# codex CLI Wrapper — 運用リファレンス

Issue #1484 で導入した codex CLI wrapper の運用手順。

## 構成

| ファイル | 役割 |
|---|---|
| `~/.local/bin/codex` | bash wrapper スクリプト（透過実行 + ログ記録） |
| `~/.local/bin/codex.real` | 元の codex 本体（symlink または実行ファイル） |
| `~/.codex-call-trace.log` | 全呼び出しログ |
| `plugins/twl/scripts/codex-call-trace-monitor.sh` | 定期 audit スクリプト |

## ログフォーマット

```
===== 2026-05-07T12:00:00+09:00 PID=12345 PPID=67890 =====
timestamp=2026-05-07T12:00:00+09:00
PID=12345
PPID=67890
PWD=/home/shuu5/project
ARGS=--version
PARENT=bash /path/to/caller.sh
EXIT_CODE=0
===== END exit=0 =====
```

## ロールバック手順

wrapper を削除して元の codex 本体に戻す場合:

```bash
mv ~/.local/bin/codex.real ~/.local/bin/codex
```

この 1 コマンドで元の状態に完全復旧できる。

## 再インストール手順

```bash
# 1. 元本体を退避
mv ~/.local/bin/codex ~/.local/bin/codex.real

# 2. wrapper を再配置
cp plugins/twl/scripts/codex-wrapper.sh ~/.local/bin/codex
chmod +x ~/.local/bin/codex
```

## 定期 audit

```bash
# 手動実行
bash plugins/twl/scripts/codex-call-trace-monitor.sh

# 別ログファイル指定
bash plugins/twl/scripts/codex-call-trace-monitor.sh --log /path/to/log
```

WARN 条件:
- 24h 以内の呼び出しがゼロ件（subagent silent skip の疑い）
- exit != 0 が 3 回以上連続（系統的失敗の疑い）
