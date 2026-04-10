---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 15
---
# su-compact（知識外部化 + compaction 制御）

ユーザーが明示的に知識外部化 + compaction を実行するための統合コマンド。
Long-term Memory を Memory MCP に保存し、Working Memory を `.supervisor/working-memory.md` に退避してから `/compact` を実行する。

## 引数

- `--wave`: Wave 完了サマリ保存 + compaction
- `--task`: タスク状態退避 + compaction
- `--full`: 全知識外部化 + compaction
- （引数なし）: 状況自動判定で適切なモードを選択

## フロー（MUST）

### Step 0: モード判定

引数から実行モードを決定する。引数なしの場合は自動判定する。

**自動判定ロジック**:
1. `.autopilot/issues/` に未完了 Issue JSON が存在する → `task` モード
2. `.autopilot/waves/` に完了 Wave が存在する → `wave` モード
3. それ以外 → `full` モード

実行モードをユーザーに表示する:
```
>>> su-compact モード: <mode>
```

### Step 1: Memory MCP 設定取得

`refs/memory-mcp-config.md` を Read してツール名を取得する:
- `store_tool`: 記憶保存用ツール名（例: `mcp__doobidoo__memory_store`）

### Step 2: Long-term Memory 保存（Memory MCP）

モードに応じた知識を Memory MCP に保存する。

**wave モード**:
- 完了 Wave の Issue 番号・成果・学習事項を収集
- `store_tool` で type=`project`、name=`Wave完了サマリ <timestamp>` として保存

**task モード**:
- 現在処理中の Issue 番号・状態・次のステップを収集
- `store_tool` で type=`project`、name=`タスク状態 Issue#<N> <timestamp>` として保存

**full モード**:
- 上記 wave + task の両方を実行
- セッション中に判明した重要な技術的決定を type=`feedback` として保存

Memory MCP が利用不可の場合は警告のみ表示してスキップする（エラー終了しない）。

### Step 3: Working Memory 退避

```bash
mkdir -p .supervisor
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
```

`.supervisor/working-memory.md` に現在の作業状態を書き出す:

```markdown
# Working Memory（退避: <timestamp>）

## 処理中 Issue
<!-- 現在の Issue 番号・状態 -->

## 次のステップ
<!-- compaction 復帰後に実行すべきアクション -->

## 補足コンテキスト
<!-- その他の重要な情報 -->
```

externalize-state コマンドが存在する場合（`plugins/twl/commands/externalize-state.md`）は追加で呼び出す:
```bash
# externalize-state が存在する場合のみ実行
[[ -f "plugins/twl/commands/externalize-state.md" ]] && echo "⏭ externalize-state 呼出（存在する場合）"
```

### Step 4: compaction 実行

保存完了をユーザーに確認する:
```
✓ Long-term Memory 保存完了
✓ Working Memory 退避完了（.supervisor/working-memory.md）
>>> /compact を実行します
```

`/compact` を実行する。

## 禁止事項（MUST NOT）

- Memory MCP エラーで全体を停止してはならない（警告のみ）
- externalize-state が存在しない場合にエラーを出力してはならない
- compaction 前の保存が未完了の状態で `/compact` を実行してはならない

## 参照

- `refs/memory-mcp-config.md`: Memory MCP ツール設定
