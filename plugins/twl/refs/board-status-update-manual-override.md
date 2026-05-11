# board-status-update manual-override ガイド

Issue #1567 / ADR-024 — Refined ステータス遷移の認可 caller 制限。

`manual-override` は管理者が Refined ステータスを手動設定する際の認可経路です。

## 使い方

```bash
# 認可された手動 override（BYPASS log は不要な場合）
TWL_CALLER_AUTHZ=manual-override bash plugins/twl/scripts/chain-runner.sh board-status-update <ISSUE_NUM> Refined
```

## bypass override（緊急時）

```bash
# 緊急 bypass（BYPASS log に記録される）
SKIP_REFINED_CALLER_VERIFY=1 SKIP_REFINED_REASON='<理由を記載>' \
  bash plugins/twl/scripts/chain-runner.sh board-status-update <ISSUE_NUM> Refined
```

## 認可 caller 一覧

| TWL_CALLER_AUTHZ 値 | 用途 |
|---|---|
| `workflow-issue-refine` | refine-processing-flow 経由 |
| `workflow-issue-lifecycle` | lifecycle-processing-flow 経由 |
| `co-autopilot` | co-autopilot orchestrator 経由 |
| `manual-override` | 手動 override（本ドキュメント） |

## log ファイル

- デフォルト: `/tmp/refined-status-gate.log`
- override: `REFINED_STATUS_GATE_LOG=<path>` 環境変数

参照: ADR-024 / Issue #1557 / Issue #1567
