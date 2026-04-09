---
name: twl:co-observer
description: |
  Observer メタ認知コントローラー（ADR-013）。
  autopilot セッションを監視し、3 層介入プロトコル（Auto/Confirm/Escalate）に従って
  問題を検出・分類・対処する。

  Use when user: says co-observer/observer/介入/intervention/監視,
  wants to monitor a running autopilot session,
  wants to intervene in a Worker's state.
type: controller
effort: high
spawnable_by:
- user
---

# co-observer

> **注意**: このコンポーネントは ADR-013 で定義された observer 型のスタブです。
> 完全な実装は後続 Issue で行われます。
> 介入パターン定義は `refs/intervention-catalog.md` を参照してください。

## 役割

autopilot で動作する Worker セッションを監視し、問題を検出したとき intervention-catalog.md の
3 層分類（Auto/Confirm/Escalate）に基づいて介入を実行する。

## 介入プロトコル

`refs/intervention-catalog.md` を参照してください。

## 利用可能な介入コマンド

| コマンド | 層 | 用途 |
|---------|-----|------|
| `intervene-auto` | Layer 0 Auto | non_terminal_chain_end 回復、PR 未作成 |
| `intervene-confirm` | Layer 1 Confirm | Worker idle、Wave 再計画 |
| `intervene-escalate` | Layer 2 Escalate | コンフリクト解決、設計課題 |
