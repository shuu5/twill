---
name: twl:workflow-prompt-audit
description: |
  プロンプトコンプライアンス監査ワークフロー（scan → review → apply の 3 step）。
  stale/未レビューのコンポーネントを特定し、worker-prompt-reviewer で LLM レビューを実行、
  結果に基づき refined_by を自動更新または tech-debt Issue を起票する。

  Use when user: says prompt audit, プロンプト監査, prompt compliance, refined,
  or when called from co-project prompt-audit mode.
type: workflow
effort: medium
spawnable_by: [controller]
can_spawn: [composite, atomic, specialist]
tools: [Agent, Bash, Skill]
maxTurns: 30
---

# workflow-prompt-audit

stale/未レビューコンポーネントへの継続的プロンプト品質監査ワークフロー（3 step）。

## 前提条件確認（MUST）

`twl refine --help` が成功することを確認。失敗した場合はエラーメッセージを表示して即終了（fail-fast）。

## Step 1: prompt-audit-scan（対象抽出）

`/twl:prompt-audit-scan [--limit N]` を実行。

`twl --audit --section 7 --format json` から stale/unreviewed コンポーネントを抽出し、
優先度順（stale → unreviewed、tie-break: 名前順）に最大 N 件（デフォルト 15）を返す。

対象 0 件（全 OK）→ 「全コンポーネント最新」と報告して正常終了。

## Step 2: prompt-audit-review（並列 LLM レビュー）

`/twl:prompt-audit-review <scan-result>` を実行。

Step 1 の対象コンポーネントに対して worker-prompt-reviewer を parallel Task spawn し、
結果（PASS/WARN/FAIL）を収集する。

タイムアウト/エラーの specialist は WARN 扱いで報告（workflow は中断しない）。

## Step 3: prompt-audit-apply（結果適用）

`/twl:prompt-audit-apply <review-result>` を実行。

| reviewer 結果 | 処理 |
|---|---|
| PASS | `twl refine --batch` で refined_by/refined_at を一括更新 |
| WARN | findings をユーザーに報告（Issue 起票なし） |
| FAIL | findings を報告 + ユーザー確認後に tech-debt Issue 起票 |

deps.yaml 更新後に `twl check` + `twl validate` を実行。失敗時はリバートしてエラー報告。

## 完了

監査サマリー（PASS/WARN/FAIL 件数、updated components、起票した Issue）を表示。
