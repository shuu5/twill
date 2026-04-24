# plugin-twl

Claude Code twl plugin（chain-driven + autopilot-first）。claude-plugin-dev の後継として新規構築。

## 設計哲学

**LLM は判断のために使う。機械的にできることは機械に任せる。**

- **Chain-driven**: ワークフローは chain（step の連鎖）として定義。各 step は atomic command として独立実行可能
- **Autopilot-first**: 単一 Issue も co-autopilot 経由で実装。手動介入を最小化

## Entry Points

<!-- ENTRY-POINTS-START -->
### Controllers

| Controller | 説明 |
|---|---|
| co-autopilot | 依存グラフに基づくIssue群一括自律実装オーケストレーター |
| co-issue | 要望をGitHub Issueに変換するワークフロー（thin orchestrator）。refine フェーズは workflow-issue-refine に完全委譲（ADR-0010）。explore-summary 入力必須。DAG 依存解決 + level dispatch + aggregate |
| co-explore | 問題探索の独立コントローラー。explore-summary を .explore/<N>/summary.md に保存し Issue リンクで co-issue / co-architect に接続 |
| co-project | プロジェクト管理（create / migrate / snapshot / plugin-create / plugin-diagnose / prompt-audit） |
| co-architect | 対話的アーキテクチャ構築ワークフロー（explore-summary 入力、branch/PR + review フロー付き） |
| co-utility | standalone ユーティリティコマンドの統合エントリポイント |
| co-self-improve | ライブセッション観察と能動的 self-improvement framework のエントリポイント controller |

### Supervisors

| Supervisor | 説明 |
|---|---|
| su-observer | メタ認知レイヤー: 全 controller の監視・介入。hook プライマリ / polling フォールバックの Hybrid 検知（#570）。テストシナリオ実行は co-self-improve に委譲 |
<!-- ENTRY-POINTS-END -->

## Components

| カテゴリ | 数 | 内訳 |
|---|---|---|
| Skills | 12 | controller 5 + workflow 7 |
| Commands | 92 | atomic 83 + composite 9 |
| Agents | 29 | specialist 29 |
| Refs | 19 | reference 19（ref-invariants 含む） |
| Scripts | 28 | script 28 |
| **合計** | **180** | |

## 使い方

Issue 起点の開発フロー:

```bash
# 1. 開発準備（worktree 作成）
/twl:workflow-setup #<issue-number>

# 2. 実装・テスト（TDD サイクル）
/twl:workflow-test-ready

# 3. PR 検証
/twl:workflow-pr-verify

# 4. PR マージ
/twl:workflow-pr-merge
```

Autopilot で複数 Issue を一括実装:

```bash
/twl:co-autopilot
```

## Architecture

Notable scripts: `specialist-audit` (specialist completeness 監査 — merge-gate および su-observer から呼び出し、JSONL の specialist 実行数を期待集合と照合し JSON 形式で結果を出力)

<!-- DEPS-GRAPH-START -->
![Dependency Graph](./docs/deps.svg)
<!-- DEPS-GRAPH-END -->

<!-- DEPS-SUBGRAPHS-START -->
<details>
<summary>co-autopilot</summary>

![co-autopilot](./docs/deps-co-autopilot.svg)
</details>

<details>
<summary>co-issue</summary>

![co-issue](./docs/deps-co-issue.svg)
</details>

<details>
<summary>co-project</summary>

![co-project](./docs/deps-co-project.svg)
</details>

<details>
<summary>co-explore</summary>

![co-explore](./docs/deps-co-explore.svg)
</details>

<details>
<summary>co-architect</summary>

![co-architect](./docs/deps-co-architect.svg)
</details>

<details>
<summary>co-utility</summary>

![co-utility](./docs/deps-co-utility.svg)
</details>

<details>
<summary>co-self-improve</summary>

![co-self-improve](./docs/deps-co-self-improve.svg)
</details>

<details>
<summary>workflow-setup</summary>

![workflow-setup](./docs/deps-workflow-setup.svg)
</details>

<details>
<summary>workflow-test-ready</summary>

![workflow-test-ready](./docs/deps-workflow-test-ready.svg)
</details>

<details>
<summary>workflow-pr-verify</summary>

![workflow-pr-verify](./docs/deps-workflow-pr-verify.svg)
</details>

<details>
<summary>workflow-pr-fix</summary>

![workflow-pr-fix](./docs/deps-workflow-pr-fix.svg)
</details>

<details>
<summary>workflow-pr-merge</summary>

![workflow-pr-merge](./docs/deps-workflow-pr-merge.svg)
</details>

<details>
<summary>workflow-dead-cleanup</summary>

![workflow-dead-cleanup](./docs/deps-workflow-dead-cleanup.svg)
</details>

<details>
<summary>workflow-tech-debt-triage</summary>

![workflow-tech-debt-triage](./docs/deps-workflow-tech-debt-triage.svg)
</details>

<details>
<summary>workflow-self-improve</summary>

![workflow-self-improve](./docs/deps-workflow-self-improve.svg)
</details>

<details>
<summary>workflow-observe-loop</summary>

![workflow-observe-loop](./docs/deps-workflow-observe-loop.svg)
</details>

<details>
<summary>workflow-plugin-create</summary>

![workflow-plugin-create](./docs/deps-workflow-plugin-create.svg)
</details>

<details>
<summary>workflow-plugin-diagnose</summary>

![workflow-plugin-diagnose](./docs/deps-workflow-plugin-diagnose.svg)
</details>

<details>
<summary>workflow-prompt-audit</summary>

![workflow-prompt-audit](./docs/deps-workflow-prompt-audit.svg)
</details>

<details>
<summary>workflow-issue-lifecycle</summary>

![workflow-issue-lifecycle](./docs/deps-workflow-issue-lifecycle.svg)
</details>

<details>
<summary>workflow-issue-refine</summary>

![workflow-issue-refine](./docs/deps-workflow-issue-refine.svg)
</details>

<details>
<summary>workflow-arch-review</summary>

![workflow-arch-review](./docs/deps-workflow-arch-review.svg)
</details>
<!-- DEPS-SUBGRAPHS-END -->
