# Proposal: Prompt Compliance Audit ワークフロー統合

## Issue

#207

## Why

prompt compliance 検証機能（`twl --audit` Section 8, `worker-prompt-reviewer`）が実装済みだが、どの controller→workflow にも統合されていない。#107 で一括レビューを実施した後、ref-prompt-guide.md の更新やコンポーネント追加で refined_by が stale になっても自動検出されない。

## Context

### 既存資産
- `twl --audit --section 8`: deps.yaml の refined_by ハッシュと refs/ref-prompt-guide.md の現在ハッシュを照合（Python、LLM不要）
- `worker-prompt-reviewer`: ref-prompt-guide の5原則に基づく LLM レビュー specialist
- `pr-review-manifest.sh`: PR の変更ファイルに応じて specialist を動的選択するスクリプト

### 現状の問題
1. PR で .md ファイルを変更しても prompt compliance は検証されない
2. ref-prompt-guide.md を更新しても全コンポーネントが stale になるだけで通知もアクションもない
3. 全体監査は手動 `twl --audit` のみ、ワークフローに組み込まれていない

## Proposal

2段構成で統合する:

### Tier 1: PR cycle への機械的ゲート（低コスト・高頻度）

`pr-review-manifest.sh` に prompt ファイル変更検出ルールを追加し、既存の phase-review/merge-gate フローで prompt compliance を検証する。

- 変更対象: `pr-review-manifest.sh`
- 新規: `worker-prompt-compliance` specialist（軽量、`twl audit --section 8` ベース）
- コスト: specialist 1つの spawn（Bash 実行のみ、LLM 判断最小限）

### Tier 2: 全体監査ワークフロー（LLM レビュー・低頻度）

stale/未レビューのコンポーネントに対して `worker-prompt-reviewer` を batch 実行し、PASS なら refined_by を更新、FAIL なら tech-debt Issue を起票する。

- 変更対象: deps.yaml（新ワークフロー追加）
- 新規: `prompt-audit-batch` atomic command、`workflow-prompt-audit` workflow
- トリガー: co-utility 経由の手動実行、将来的に co-autopilot 完了後の自動トリガー追加可能

## Scope

### ADDED Requirements
- Requirement: PR cycle で prompt compliance を機械的に検証する
- Requirement: 全体監査を実行してstale コンポーネントを一括レビューする
- Requirement: PASS 時に refined_by ハッシュを自動更新する

### MODIFIED Requirements
- pr-review-manifest.sh: .md ファイル変更時の specialist 選択ルール追加
- deps.yaml: 新コンポーネント定義追加

## Risks

- Tier 1 の specialist が PR cycle の所要時間を増加させる → Bash ベースの軽量実装で緩和
- Tier 2 の batch spawn が大量トークンを消費する → 1回あたりの上限（max 10-20）で制御
- refined_by の自動更新が deps.yaml の diff を肥大化させる → 単独コミットで分離
