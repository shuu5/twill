---
tools: [mcp__doobidoo__memory_search, Agent, Bash, Task, WebFetch, WebSearch, Write, Read]
type: atomic
effort: low
maxTurns: 10
---

# research: プラグイン設計情報の動的取得

## 目的
プラグイン設計に必要な最新情報を動的に取得し、構造化サマリーを作成する。
AT仕様、Claude Code設定仕様（スキル/コマンド/エージェント/フック/frontmatter）の両方を対象。

## 手順

### 1. 公式ドキュメント取得
```bash
# AT仕様
WebFetch: https://docs.anthropic.com/en/docs/claude-code/agent-teams

# Claude Code全般（スキル/コマンド/エージェント/フック/プラグイン設定）
WebFetch: https://docs.anthropic.com/en/docs/claude-code
```

### 2. 最新変更の確認
```bash
WebSearch: "Claude Code Agent Teams" site:docs.anthropic.com
WebSearch: "Claude Code skills commands agents hooks" site:docs.anthropic.com 2026
```

### 3. Memory から過去の経験を検索
```bash
mcp__doobidoo__memory_search: "plugin design patterns"
```

### 4. 既知の仕様を確認
ref-types / ref-practices reference を参照して既知の型ルール・パターンを確認。

### 5. サマリー作成
取得した情報を以下の構造で整理:
- **AT仕様変更**: 新しいツール・パラメータ
- **Claude Code設定変更**: frontmatter、フック、スキルマッチングの更新
- **ベストプラクティス更新**: 推奨パターンの変更
- **既知の制約**: 制限事項・注意点
- **ref-types との差分**: reference の更新が必要な箇所

## Subagent Delegation（controller-improve 経由の場合）
controller-improve から呼ばれる場合、controller が Task tool で docs-researcher を直接起動する
Subagent Delegation パターンを使用。このコマンドは standalone 使用向け。

controller-improve での呼び出しフロー:
1. controller が `Task(docs-researcher, "{調査内容}")` で specialist を起動
2. docs-researcher が isolated context で調査実行
3. 結果サマリーのみ controller に返却
4. controller が `{snapshot_dir}/03-research-results.md` に Write

## 出力
構造化サマリーをユーザーに表示（standalone 時）。
controller-improve 経由時はスナップショットファイルに出力。
