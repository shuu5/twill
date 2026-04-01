## 1. hook if 条件フィールド

- [ ] 1.1 Claude Code v2.1.85+ の hook `if` 条件構文をドキュメントで確認・検証
- [ ] 1.2 hooks/hooks.json に `if` 条件付き hook エントリのパターン追加（既存 2 hook は維持）

## 2. Controller effort フィールド

- [ ] 2.1 skills/co-autopilot/SKILL.md に `effort: high` 追加
- [ ] 2.2 skills/co-issue/SKILL.md に `effort: high` 追加
- [ ] 2.3 skills/co-project/SKILL.md に `effort: medium` 追加
- [ ] 2.4 skills/co-architect/SKILL.md に `effort: high` 追加
- [ ] 2.5 skills/workflow-setup/SKILL.md に `effort: medium` 追加
- [ ] 2.6 skills/workflow-test-ready/SKILL.md に `effort: medium` 追加
- [ ] 2.7 skills/workflow-pr-cycle/SKILL.md に `effort: medium` 追加
- [ ] 2.8 skills/workflow-dead-cleanup/SKILL.md に `effort: low` 追加
- [ ] 2.9 skills/workflow-tech-debt-triage/SKILL.md に `effort: medium` 追加

## 3. specialist skills フィールド注入

- [ ] 3.1 全 28 specialist の body 内 ref-* 参照を抽出・マッピング表作成
- [ ] 3.2 ref-* 参照がある specialist の frontmatter に skills フィールド追加

## 4. Controller tools フィールド（Agent スポーン制限）

- [ ] 4.1 co-autopilot の tools フィールドに Agent スポーン制限追加
- [ ] 4.2 co-issue の tools フィールドに Agent スポーン制限追加
- [ ] 4.3 co-architect の tools フィールドに Agent スポーン制限追加
- [ ] 4.4 co-project の tools フィールドに Agent スポーン制限追加

## 5. deps.yaml 同期

- [ ] 5.1 deps.yaml に effort フィールド反映（全 Controller）
- [ ] 5.2 deps.yaml に skills フィールド反映（specialist）
- [ ] 5.3 deps.yaml に tools フィールド反映（Controller）

## 6. 検証

- [ ] 6.1 `loom check` PASS 確認
- [ ] 6.2 `loom validate` PASS 確認
- [ ] 6.3 全変更のコミット・プッシュ
