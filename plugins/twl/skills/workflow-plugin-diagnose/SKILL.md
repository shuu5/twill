---
name: twl:workflow-plugin-diagnose
description: |
  既存プラグイン診断・修正ワークフロー（migrate-analyze → diagnose → fix → verify）。

  Use when user: says プラグイン診断したい/修正したい/改善したい,
  or when called from co-project plugin-diagnose mode.
type: workflow
effort: medium
spawnable_by: [controller]
can_spawn: [composite, atomic]
tools: [Agent, Bash, Skill]
maxTurns: 30
---

# workflow-plugin-diagnose

既存プラグインの診断・修正・検証の 6 ステップワークフロー。

## Step 1: plugin-migrate-analyze（AT 移行分析、optional）

既存プラグインが旧 guide-patterns 準拠の場合のみ実行。

`/twl:plugin-migrate-analyze` を実行。

既存 deps.yaml を分析し、新型への移行マッピングを自動生成。
移行が不要な場合はスキップして Step 2 へ。

## Step 2: plugin-diagnose（問題診断）

`/twl:plugin-diagnose` を実行。

対象プラグインの以下を検証:
- 構造検証（`twl check` / `twl validate`）
- frontmatter 整合性
- 5 原則チェック（team-worker プロンプト品質）
- アーキテクチャパターン評価
- orphan ノード検出（`twl orphans`）
- deep-validate（`twl audit`）

## Step 3: plugin-phase-diagnose（並列診断、composite）

`/twl:plugin-phase-diagnose` を実行。

worker-structure・worker-principles・worker-architecture を並列起動し、
構造・品質・アーキテクチャを同時診断。

## Step 4: plugin-fix（修正適用）

`/twl:plugin-fix` を実行。

diagnose / phase-diagnose の結果をもとに問題を修正:
- 構造的問題（deps.yaml 修正、ファイル配置）
- プロンプト品質（5 原則準拠）
- アーキテクチャパターン適用

## Step 5: plugin-verify（統合検証）

`/twl:plugin-verify` を実行。

修正後の総合検証:
- 構造検証（`twl check` / `twl validate`）
- 5 原則準拠チェック
- 修正前後の差分確認
- PASS/FAIL 判定 → FAIL 時は Step 4 に戻る

## Step 6: plugin-phase-verify（並列検証、composite）

`/twl:plugin-phase-verify` を実行。

worker-structure・worker-principles・worker-architecture を並列起動し、
修正結果を検証。全 worker PASS で完了。

## 完了

診断・修正・検証のサマリーを表示。
