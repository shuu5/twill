## Context

`issue-critic.md` L62-69 と `issue-feasibility.md` L53-60 に同一の「調査バジェット制御（MUST）」セクションが存在する。現在の refs 機構（`refs/ref-issue-quality-criteria.md` など）と同様のパターンで共通化する。

既存の `ref-issue-quality-criteria` の参照方式: frontmatter に `skills: [ref-issue-quality-criteria]` を追加し、agent 本文に「`**/refs/ref-issue-quality-criteria.md` を Glob/Read して基準を確認すること」という参照指示を記述する。

## Goals / Non-Goals

**Goals:**
- 重複する調査バジェット制御セクションを単一の `refs/ref-investigation-budget.md` に集約
- 両 agent の本文から重複セクションを削除し、ref 参照指示に置換
- テスト・deps.yaml を整合させる

**Non-Goals:**
- 調査バジェット制御のロジック変更（内容は行単位一致で現行維持）
- 他の specialist agent への適用拡大

## Decisions

1. **行単位一致で移動**: `refs/ref-investigation-budget.md` の内容は `issue-critic.md` L62-69 から行単位一致でコピー。変更なし
2. **参照方式は既存パターン準拠**: frontmatter `skills:` に追加 + 本文に Glob/Read 指示を挿入（`ref-issue-quality-criteria` と同形式）
3. **テスト更新方針**: `co-issue-specialist-maxturns-fix.test.sh` の `assert_file_contains` を、agent 本文内の「調査バジェット制御」文言チェックから、ref ファイルの存在確認または agent frontmatter の skills 参照チェックに変更

## Risks / Trade-offs

- **リスク低**: 内容変更なし、機械的な移動のみ。テスト更新は対象ファイル 1 件のみ
- **トレードオフ**: agent が ref ファイルを Read しない場合に調査バジェット制御が無視されるリスクがあるが、現行 refs 機構も同様の制約であり許容範囲
