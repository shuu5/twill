# ADR-003: Unified State File

## Status
Accepted

## Context

旧プラグイン (claude-plugin-dev) では状態が以下の6種に散在しており、一貫性の維持が困難だった:

1. マーカーファイル（`.auto-mode`, `.merge-pending` 等）
2. 環境変数（`DEV_AUTOPILOT_SESSION`）
3. tmux ウィンドウ名による状態推定
4. `.fail` ファイルによるエラー状態管理
5. git ブランチ名からの状態推定
6. PR ラベルによる状態同期

問題:
- 状態の不整合（マーカーファイルと環境変数で矛盾が発生）
- Compaction 時の環境変数喪失
- 状態確認のための複数箇所の参照が必要
- テスト時の状態再現が困難

## Decision

`issue-{N}.json` + `session.json` の2ファイルに統合する。9件の不変条件で安全性を保証する。

### issue-{N}.json (per-issue)

```json
{
  "issue": 42,
  "status": "running|merge-ready|done|failed",
  "branch": "feat/42-xxx",
  "pr": null,
  "window": "ap-#42",
  "started_at": "2026-03-26T10:00:00Z",
  "current_step": "review-complete",
  "retry_count": 0,
  "fix_instructions": null,
  "merged_at": null,
  "files_changed": [],
  "failure": null
}
```

### session.json (per-autopilot-run)

```json
{
  "session_id": "a1b2c3d4",
  "plan_path": "plan.yaml",
  "current_phase": 1,
  "phase_count": 3,
  "cross_issue_warnings": [],
  "phase_insights": [],
  "patterns": {},
  "self_improve_issues": []
}
```

### 安全性保証: 不変条件9件

不変条件 A~I（詳細は `domain/contexts/autopilot.md` 参照）により、状態の一貫性・安全性・再現性を保証する。

## Consequences

### Positive
- 状態の一元管理（参照箇所が2ファイルに限定）
- Compaction 耐性（環境変数に依存しない）
- テスト時の状態再現が容易（JSON ファイルの配置のみ）
- 不変条件による安全性の形式的保証

### Negative
- JSON read/write ヘルパーの実装が必要
- ファイルシステムへの書き込み頻度増加
- issue-{N}.json の Pilot/Worker 間アクセス制御が必要（Pilot=read, Worker=write）

### Mitigations
- read/write ヘルパーを script 型コンポーネントとして実装（再利用性確保）
- Pilot/Worker のアクセス方向を不変条件で保証（テストで検証）


## Amendments

- **ADR-026 cross-reference**: session.json への atomic RMW governance は [ADR-028-atomic-rmw-strategy.md](./ADR-028-atomic-rmw-strategy.md) を参照。4 経路 (retrospective / postprocess / patterns / externalize-state) の write authority matrix と flock(8) 保護戦略を定義する。

## 関連 ADR

- **[ADR-018: state schema SSOT](./ADR-018-state-schema-ssot.md)**: `status` フィールドを外部観察の唯一の正典に指定。`workflow_done` フィールドの廃止と inject トリガー機構の `current_step` ベース化。
- **[ADR-028: atomic RMW strategy](./ADR-028-atomic-rmw-strategy.md)**: session.json の 4 RMW 経路を flock(8) で保護する戦略。
