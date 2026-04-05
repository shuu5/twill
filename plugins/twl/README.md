# plugin-twl

Claude Code twl plugin（chain-driven + autopilot-first）。claude-plugin-dev の後継として新規構築。

## 設計哲学

**LLM は判断のために使う。機械的にできることは機械に任せる。**

- **Chain-driven**: ワークフローは chain（step の連鎖）として定義。各 step は atomic command として独立実行可能
- **Autopilot-first**: 単一 Issue も co-autopilot 経由で実装。手動介入を最小化

## Entry Points

### Controllers

| Controller | 役割 |
|---|---|
| co-autopilot | 依存グラフに基づく Issue 群一括自律実装オーケストレーター |
| co-issue | 要望を GitHub Issue に変換するワークフロー |
| co-project | プロジェクト管理（create / migrate / snapshot） |
| co-architect | 対話的アーキテクチャ構築ワークフロー |

### Workflows

| Workflow | 役割 |
|---|---|
| workflow-setup | 開発準備（worktree 作成 → OpenSpec → テスト準備） |
| workflow-test-ready | テスト生成と準備確認 |
| workflow-pr-cycle | PR サイクル（verify → review → test → fix → visual → report → merge） |
| workflow-dead-cleanup | Dead Component 検出結果に基づく確認付き削除 |
| workflow-tech-debt-triage | tech-debt Issue の棚卸し |

## Components

| カテゴリ | 数 | 内訳 |
|---|---|---|
| Skills | 12 | controller 5 + workflow 7 |
| Commands | 92 | atomic 83 + composite 9 |
| Agents | 29 | specialist 29 |
| Refs | 18 | reference 18 |
| Scripts | 28 | script 28 |
| **合計** | **179** | |

## 使い方

Issue 起点の開発フロー:

```bash
# 1. 開発準備（worktree 作成 + OpenSpec propose）
/twl:workflow-setup #<issue-number>

# 2. 実装（tasks.md に沿って実装）
/twl:change-apply <change-id>

# 3. PR サイクル（レビュー + テスト + 修正）
/twl:workflow-pr-cycle

# 4. アーカイブ + worktree 削除
/twl:change-archive
/twl:worktree-delete
```

Autopilot で複数 Issue を一括実装:

```bash
/twl:co-autopilot
```

## Architecture

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
<summary>co-architect</summary>

![co-architect](./docs/deps-co-architect.svg)
</details>

<details>
<summary>co-utility</summary>

![co-utility](./docs/deps-co-utility.svg)
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
<!-- DEPS-SUBGRAPHS-END -->
