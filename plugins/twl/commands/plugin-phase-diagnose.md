---
type: composite
tools: [Agent, Bash, Task, Read]
effort: medium
maxTurns: 30
---
# phase-diagnose: 並列診断（composite）

## 目的
worker-structure、worker-principles、worker-architecture を並列起動し、プラグインの構造・品質・アーキテクチャを同時に診断する。

## 入力
controller-improve から以下を受け取る:
- `plugin_path`: 対象プラグインのパス
- `snapshot_dir`: Context Snapshot ディレクトリ（例: `/tmp/dev-improve-{name}/`）

## 手順

### 1. specialist 並列起動
controller が Task tool で以下の 3 specialist を同時起動:

**worker-structure**:
```
Task({
  name: "worker-structure",
  subagent_type: "general-purpose",
  prompt: "{plugin_path} の構造検証を実行してください。
    twl check/validate/orphans、frontmatter整合性、cross-reference を確認し、
    Critical/Warning/Info で分類した結果をまとめてください。"
})
```

**worker-principles**:
```
Task({
  name: "worker-principles",
  subagent_type: "general-purpose",
  prompt: "{plugin_path} の 5原則+controller品質チェックを実行してください。
    agents/ 配下のファイルを5原則チェックリストに照合し、
    controller の行数・インライン実装・ドキュメントセクション・ツール整合性も検証し、
    結果をまとめてください。"
})
```

**worker-architecture**:
```
Task({
  name: "worker-architecture",
  subagent_type: "general-purpose",
  prompt: "{plugin_path} のアーキテクチャパターン適用状態を評価してください。
    deps.yaml の team_config・型分布・controller の calls 順序・specialist 委任状態を分析し、
    パターンの適用状態と最適化機会をまとめてください。"
})
```

### 2. 結果統合
3 specialist の結果を統合し、Critical/Warning/Info で分類:

```markdown
# 診断結果

## 構造検証
{worker-structure の報告}

## 5原則+Controller品質検証
{worker-principles の報告}

## アーキテクチャ検証
{worker-architecture の報告}

## 総合判定
- Critical: {N} 件
- Warning: {N} 件
- Info: {N} 件
```

## 出力
統合された診断結果を controller に返す。
