# phase-verify: 並列検証（composite）

## 目的
fix 適用後に worker-structure、worker-principles、worker-architecture を並列起動し、修正結果を検証する。

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
  prompt: "{plugin_path} の構造を再検証してください。
    loom check/validate/orphans、frontmatter整合性、cross-reference を確認し、
    Critical/Warning/Info で分類した結果をまとめてください。"
})
```

**worker-principles**:
```
Task({
  name: "worker-principles",
  subagent_type: "general-purpose",
  prompt: "{plugin_path} の 5原則+controller品質を再チェックしてください。
    agents/ 配下のファイルを5原則チェックリストで再チェックし、
    controller の行数・インライン実装・ドキュメントセクション・ツール整合性も検証し、
    結果をまとめてください。"
})
```

**worker-architecture**:
```
Task({
  name: "worker-architecture",
  subagent_type: "general-purpose",
  prompt: "{plugin_path} のアーキテクチャパターン適用状態を再評価してください。
    fix 適用後の deps.yaml・controller・commands を分析し、
    パターンの適用状態と残存する最適化機会をまとめてください。"
})
```

### 2. 結果統合
3 specialist の結果を統合:

```markdown
# 検証結果

## 構造検証
{worker-structure の報告}

## 5原則+Controller品質検証
{worker-principles の報告}

## アーキテクチャ検証
{worker-architecture の報告}

## 修正前との比較
01-diagnose-results.md を Read して、改善された項目を列挙。

## 総合判定
- PASS: Critical が 0 件
- FAIL: Critical が 1 件以上
```

## 出力
検証結果と PASS/FAIL 判定を controller に返す。
