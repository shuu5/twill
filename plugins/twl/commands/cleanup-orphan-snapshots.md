---
type: atomic
tools: [Bash]
effort: low
maxTurns: 5
---
# .dev-session 孤児スナップショット cleanup

`.dev-session/` 直下（`issue-N/` namespace 外）に残存する孤児ファイル・空ディレクトリを検出・削除する。

**対象ディレクトリ**: `~/.claude/plugins/twl/.dev-session/` のみ。  
**`autopilot-cleanup.sh` との違い**: `autopilot-cleanup.sh` は `.autopilot/` が対象。両者は重複しない。

## 前提チェック（MUST）

symlink であることを確認してから操作する:

```bash
readlink ~/.claude/plugins/twl 2>/dev/null \
  || { echo "ERROR: ~/.claude/plugins/twl は symlink ではありません"; exit 1; }
```

## Step 1: 孤児検出（dry-run、デフォルト）

```bash
DEV_SESSION_DIR=~/.claude/plugins/twl/.dev-session

echo "=== namespace 外の孤児ファイル（--apply で削除） ==="
find "$DEV_SESSION_DIR" -maxdepth 1 -type f 2>/dev/null || echo "(なし)"

echo ""
echo "=== 7日以上古い孤児ファイル ==="
find "$DEV_SESSION_DIR" -maxdepth 1 -type f -mtime +7 2>/dev/null || echo "(なし)"

echo ""
echo "=== 空の issue-*/ ディレクトリ ==="
find "$DEV_SESSION_DIR" -maxdepth 1 -type d -name 'issue-*' -empty 2>/dev/null || echo "(なし)"
```

## Step 2: 削除（--apply のみ実行）

`--apply` フラグなしではこのステップをスキップすること。

```bash
# Wave AA.3 残骸（既知の孤児、実測存在確認済み 2026-04-25）
rm -f ~/.claude/plugins/twl/.dev-session/07.3-pattern-analysis.md
rm -f ~/.claude/plugins/twl/.dev-session/ac-test-mapping.yaml

# 一般パターン: 7日以上古いファイル
find ~/.claude/plugins/twl/.dev-session/ -maxdepth 1 -type f -mtime +7 -delete

# 一般パターン: 空の issue-*/ ディレクトリ
find ~/.claude/plugins/twl/.dev-session/ -maxdepth 1 -type d -name 'issue-*' -empty -delete

echo "✓ cleanup 完了"
```

## 禁止事項（MUST NOT）

- `--apply` なしで削除コマンドを実行してはならない（dry-run がデフォルト）
- `~/.claude/plugins/twl` の symlink target（worktree 内部）を直接削除・移動してはならない
- `issue-N/` namespace 内のファイルを削除してはならない（per-issue 設計 #938 準拠）
- `.autopilot/` ディレクトリを操作してはならない（`autopilot-cleanup.sh` の責務）
