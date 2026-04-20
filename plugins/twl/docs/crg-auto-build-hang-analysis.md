# CRG Auto-Build Hang Analysis (Issue #754)

Wave residual-3 (#728-#731 並列実行) において、全 4 Worker が `crg-auto-build` ステップで
15 分以上ハングした事象の仮説検証と真因特定。

## 仮説一覧

### H1: CRG 並列実行のスケーラビリティ問題

**内容**: 4 つの CRG MCP server が同一ホスト上で同時に twill モノリポをフルビルドする際、
tree-sitter の共有リソース（cache, file locks, model assets）で競合 or デッドロック。

**検証根拠**:
- 全 4 CRG プロセスが同時に同症状（WAL 358472 bytes で完全凍結、10 秒変化なし）
- Load average 2.25（健全）、disk wait 0%、メモリ余裕あり → リソース枯渇ではない
- 各 CRG プロセスが `state=S (sleeping), wchan=ep_poll` → 受信待ち（アイドル）

**判定**: **真因の一部（寄与あり）**。全 Worker が同一タイミングでビルドを開始したことが
H3（RPC stdio ハング）を誘発した可能性が高い。

---

### H2: Worker LLM thinking が異常に低速

**内容**: Anthropic API のレートリミット or thinking budget 過大設定により、
`thinking with max effort` で出力が極端に遅延（558 tokens / 15 min = 40 tokens/min）。

**検証根拠**:
- tmux pane: `Calling code-review-graph… (15m XXs · ↓ 558 tokens · thinking with max effort)`
- 通常: 100-1000 tokens/min に対して 40 tokens/min は異常値

**判定**: **外部要因（測定・記録のみ）**。本 Issue の対処範囲外。
Anthropic API 側の問題であり、ガード側で制御できない。
ただし「LLM が MCP 応答待ちで turn を消費しない」という動作が
`maxTurns: 10` による自然 timeout を無効化した直接原因でもある。

---

### H3: CRG → Worker 間の MCP 応答ロスト

**内容**: CRG がリクエスト処理を完了したが、stdio buffer flush 等で Worker に到達せず、
Worker が無限待機（stdio half-deadlock）。

**検証根拠**:
- CRG プロセス: `ep_poll`（受信待ち）、サブスレッド: `unix_stream_data_wait`
- Worker Claude: `Calling code-review-graph` 表示継続（RPC 応答未着）
- WAL ファイルが 358472 bytes で凍結 → ビルド処理自体が途中停止または未完了

**判定**: **真因の核心（主因）**。CRG MCP server が stdio 経由で応答を返せない状態に
陥ったまま、Worker LLM が無限に応答を待ち続けた。`maxTurns: 10` は「LLM が
tool result を受け取って turn を消費する」前提のガードであり、RPC ハング時には無効。

---

## 真因の結論

**H1 + H3 の複合**が真因。

1. 4 Worker が同時に CRG フルビルドを MCP RPC で要求（H1 の並列競合）
2. CRG プロセスが内部デッドロックまたは書き込み待機で応答を返せなくなる（H3 の RPC ハング）
3. Worker LLM は tool result を受け取れず無限待機
4. `maxTurns: 10` は効かない（RPC 応答待ちで turn を消費しないため）

## 対処方針

**採用**: candidate (a) — `timeout 600 uvx code-review-graph build` による Bash CLI ラップ

**理由**:
- MCP ツール経由ではなく CLI を直接呼ぶことで、MCP RPC ハングを完全に回避
- Bash `timeout` コマンドにより LLM turn 予算に依存しない wall-clock ガードを実現
- `exit 124`（timeout 到達）を graceful fail として扱い、workflow を継続
- candidate (b)（chain-runner.sh 側 wall-clock ガード）は影響範囲が広く、この Issue の
  ターゲット（crg-auto-build 単体）に対して過剰なため不採用

## 不採用の候補

- **(b) chain-runner.sh 側の wall-clock ガード**: 全 llm dispatch ステップに影響するため
  影響範囲が過剰。crg-auto-build 固有の問題に対して汎用ガードを入れることは
  責務の分離を損なう
- **(c) 直列化**: 並列度を 1 に制限。並列実行の恩恵（速度向上）を完全に失う
- **(d) skip-on-failure のみ**: timeout なし。同じハング問題が再発する
