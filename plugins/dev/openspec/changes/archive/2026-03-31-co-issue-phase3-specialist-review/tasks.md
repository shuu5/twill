## 1. リファレンス・agent 定義の作成

- [x] 1.1 `refs/ref-issue-quality-criteria.md` を新規作成（severity 判定基準、CRITICAL/WARNING/INFO の使い分け、過剰 CRITICAL 防止ルール）
- [x] 1.2 `agents/issue-critic.md` を新規作成（agent frontmatter: model: sonnet, maxTurns: 15。仮定/曖昧点/盲点/粒度/split/依存検出。ADR-004 findings 形式、category: assumption/ambiguity/scope）
- [x] 1.3 `agents/issue-feasibility.md` を新規作成（agent frontmatter: model: sonnet, maxTurns: 15。実コード読みで実装可能性/影響範囲検証。ADR-004 findings 形式、category: feasibility）

## 2. co-issue Phase 3 再構成

- [x] 2.1 `skills/co-issue/SKILL.md` の Phase 3 を再構成: issue-dig / issue-assess 呼び出しを削除し、specialist 並列レビューフローに置換
- [x] 2.2 Phase 3 フローを実装: (1) issue-structure + ラベル抽出 → (2) 全 Issue × 2 specialist 一括並列 spawn → (3) 結果集約 → (4) CRITICAL ブロック判定 → (5) ユーザー提示
- [x] 2.3 `--quick` フラグ対応: specialist レビュースキップのパスを追加
- [x] 2.4 split 提案ハンドリング: specialist の scope category split 提案 → ユーザー承認 → 最大 1 ラウンド分割（再レビューなし）

## 3. deps.yaml 更新

- [x] 3.1 `issue-critic` specialist エントリを追加（type: specialist, model: sonnet, path: agents/issue-critic.md）
- [x] 3.2 `issue-feasibility` specialist エントリを追加（type: specialist, model: sonnet, path: agents/issue-feasibility.md）
- [x] 3.3 `ref-issue-quality-criteria` reference エントリを追加（type: reference, path: refs/ref-issue-quality-criteria.md）
- [x] 3.4 `co-issue` の calls を更新: issue-dig / issue-assess 削除、specialist: issue-critic / issue-feasibility / reference: ref-issue-quality-criteria 追加。can_spawn に specialist 追加
- [x] 3.5 `issue-dig` エントリを削除
- [x] 3.6 `issue-assess` エントリを削除

## 4. ファイル削除

- [x] 4.1 `commands/issue-dig.md` を削除
- [x] 4.2 `commands/issue-assess.md` を削除

## 5. 検証

- [x] 5.1 `loom check` が PASS すること
- [x] 5.2 `loom validate` が PASS すること
- [x] 5.3 既存テストが PASS すること（`bats tests/`）
