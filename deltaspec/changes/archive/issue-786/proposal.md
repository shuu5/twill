## Why

DeltaSpec pending 4 件（issue-725/729/732/740）が 3-7 日間 `deltaspec/changes/` に滞留しており、対応 Issue はすべて merged 済みにもかかわらず spec 統合（archive）が未実行のままとなっている。このまま放置すると `deltaspec/specs/` との乖離（spec drift）が累積し、W2/W3 以降の仕様正確性に影響する。加えて issue-729 は artifacts（proposal/specs/tasks）が未作成の不完全状態にある。

## What Changes

- issue-729 の不足 artifact（proposal/specs/tasks）を完成させる
- issue-725/729/732/740 の 4 件を `twl spec archive` で順次 `deltaspec/specs/` に統合する
- archive 後に `twl spec validate` および `twl validate` で drift 0 を確認する
- 各元 Issue（#725/#729/#732/#740）に「DeltaSpec archived in PR #N」コメントを追加する

## Capabilities

### New Capabilities

なし（手順的な tech-debt 解消タスク）

### Modified Capabilities

- `deltaspec/specs/` の各 spec ファイル: issue-725/729/732/740 の要件が統合される
- issue-725: supervisor-hooks 関連 spec が追加/修正される
- issue-729: supervisor-hooks の SESSION_ID sanitization 要件が追加される
- issue-732: session-auto-cleanup および autopilot ライフサイクル spec が追加/修正される
- issue-740: specialist-completeness 検証 spec が追加/修正される

## Impact

**変更ファイル:**
- `deltaspec/changes/issue-729/proposal.md`（新規作成）
- `deltaspec/changes/issue-729/specs/`（新規作成）
- `deltaspec/changes/issue-729/tasks.md`（新規作成）
- `deltaspec/specs/` 配下の各 spec ファイル（archive による統合）
- `deltaspec/changes/issue-725/`（archive → `deltaspec/changes/archive/issue-725/` へ移動）
- `deltaspec/changes/issue-729/`（archive → `deltaspec/changes/archive/issue-729/` へ移動）
- `deltaspec/changes/issue-732/`（archive → `deltaspec/changes/archive/issue-732/` へ移動）
- `deltaspec/changes/issue-740/`（archive → `deltaspec/changes/archive/issue-740/` へ移動）

**依存関係:**
- issue-729 は design.md のみ存在。proposal/specs/tasks を先に完成させてから archive する必要がある
- issue-725/732/740 は isComplete=true のため即座に archive 可能
