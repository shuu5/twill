## Context

`plugins/twl/refs/test-scenario-catalog.md` は co-self-improve framework がテスト実行時に参照するシナリオカタログ。現在 smoke-001/002 と regression-001/002 のみ定義されており、autopilot の full-chain 遷移および Bug #436/#438/#439 を再現するシナリオが存在しない。

追加するシナリオはすべて既存の YAML フォーマット（level, description, issues_count, expected_duration_min/max, expected_conflicts, expected_pr_count, observer_polling_interval, issue_templates）に準拠する。

## Goals / Non-Goals

**Goals:**
- regression-003: DeltaSpec を伴う medium complexity Issue で setup→test-ready→pr-verify→pr-merge の全遷移を検証
- regression-004: `twl spec new` を呼ぶ Issue body を定義し、`issue:` フィールド欠落（Bug #436）を誘発できる条件を記述
- regression-005: 長時間実行が必要な Issue body を定義し、Orchestrator polling が 120 秒で timeout（Bug #438）を誘発できる条件を記述
- regression-006: PR review をスキップさせる Issue body を定義し、`phase-review.json` 不在で merge-gate が PASS してしまう（Bug #439）を誘発できる条件を記述

**Non-Goals:**
- observation-pattern-catalog.md への検出パターン追加
- `--real-issues` モードの実装
- load level シナリオの定義
- Bug 修正そのもの（別 Issue）

## Decisions

1. **regression-003 complexity**: medium（DeltaSpec + テスト生成 + PR review の全フロー）。trivial では chain 遷移が短縮されるため不適。
2. **Bug 再現はシナリオ条件で記述**: actual fix は別 Issue 担当。各シナリオには「どの条件が Bug を誘発するか」を issue_templates の body に明記する。
3. **expected_duration**: 各 Bug 再現の特性に応じて設定:
   - regression-004 (#436): archive 失敗が即座に起きるため短め（10-20 分）
   - regression-005 (#438): timeout 誘発のため長め（15-30 分）
   - regression-006 (#439): merge-gate まで通るため中程度（10-25 分）
4. **1 シナリオ 1 Issue**: Bug 再現シナリオは `issues_count: 1` で単純化。干渉なし（`expected_conflicts: 0`）。

## Risks / Trade-offs

- Bug 再現シナリオの issue_templates body は「Bug を誘発する条件」を含むため、Bug 修正後は false positive になる可能性がある。将来的にシナリオを `verified-fixed` ステータスに遷移させる仕組みが必要かもしれない（スコープ外）。
- regression-005 の timeout 誘発は環境依存（Bash timeout 設定）のため、再現性が確実ではない場合がある。
