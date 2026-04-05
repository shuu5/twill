## Why

co-issue の Phase 3（精緻化）は同一セッション内で全ステップが実行されるため、Issue 作成者と同じ仮定・盲点を持ったままレビューしてしまう。コードレビューの原則（author ≠ reviewer）を Issue 精緻化にも適用し、コンテキスト非継承の specialist agent による並列レビューを導入する。

## What Changes

- Phase 3 を簡素化: issue-dig / issue-assess を廃止し、2 specialist（issue-critic, issue-feasibility）による並列レビューに置換
- 全 Issue × 2 specialist を一括並列 spawn（Agent tool、コンテキスト非継承）
- findings severity に基づくブロック判定（CRITICAL >= 80 で Phase 4 進行不可）
- `--quick` フラグで specialist レビューをスキップ可能
- Issue 品質基準リファレンス（ref-issue-quality-criteria）を新設し specialist に注入

## Capabilities

### New Capabilities

- **issue-critic agent**: 仮定・曖昧点・盲点の検出 + 粒度・split 提案・隠れた依存の発見
- **issue-feasibility agent**: 実コード読みによる実装可能性・影響範囲の検証
- **ref-issue-quality-criteria**: specialist に注入する Issue 品質基準リファレンス
- **並列実行モデル**: 全 Issue の specialist を一括並列実行（N Issue × 2 specialist）
- **findings severity ブロック**: CRITICAL findings がある場合 Phase 4 に進めない

### Modified Capabilities

- **co-issue Phase 3**: issue-dig / issue-assess を廃止し specialist 並列レビューに置換
- **co-issue SKILL.md**: Phase 3 フロー再構成、--quick フラグ対応

## Impact

- `skills/co-issue/SKILL.md`: Phase 3 フロー再構成
- `agents/issue-critic.md`: 新規作成
- `agents/issue-feasibility.md`: 新規作成
- `refs/ref-issue-quality-criteria.md`: 新規作成
- `deps.yaml`: 新 agent 2 件 + ref 1 件追加、co-issue の calls 更新
- `commands/issue-dig.md`: 削除候補
- `commands/issue-assess.md`: 削除候補
