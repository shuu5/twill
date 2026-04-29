---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 15
---
# su-compact（知識外部化 + compaction 制御）

ユーザーが明示的に知識外部化を実行するための統合コマンド。
Long-term Memory を Memory MCP に保存し、Working Memory を `.supervisor/working-memory.md` に退避した後、**ユーザーへ `/compact` 手動実行を提案**する。

> **重要**: `/compact` は Claude Code の built-in CLI コマンドであり、skill/tool からの自動起動は不可能。本 skill は Step 3 まで自動実行し、Step 4 で **ユーザーへの指示出力のみ** 行う。

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

以下を inline 実行する（`commands/externalize-state.md` への nested invoke は行わない — Issue #1120）:

```bash
# events cleanup（§8 step 6 — .supervisor/events/ 一括クリア）
rm -f .supervisor/events/* 2>/dev/null || true
```

### Step 4: compaction 提案（ユーザー手動実行）

保存完了をユーザーに報告し、`/compact` 手動実行を提案する:
```
✓ Long-term Memory 保存完了
✓ Working Memory 退避完了（.supervisor/working-memory.md）
>>> `/compact` を手動で実行してください（built-in CLI のため自動起動不可）
```

**ユーザーが `/compact` を即実行しない場合**: skill は待機せず終了する。外部化だけで Wave 遷移を継続できるよう設計されている（SU-6a は externalize のみを MUST とする）。

## 禁止事項（MUST NOT）

- Memory MCP エラーで全体を停止してはならない（警告のみ）
- externalize-state が存在しない場合にエラーを出力してはならない
- `/compact` の自動実行を試みてはならない（built-in CLI のため skill/tool から起動不可）
- 外部化が未完了の状態で処理を完了したと報告してはならない
- `commands/externalize-state.md` への nested invoke（Read + 実行）を行ってはならない（permission prompt 回避、Issue #1120）

## 参照

- `refs/memory-mcp-config.md`: Memory MCP ツール設定
