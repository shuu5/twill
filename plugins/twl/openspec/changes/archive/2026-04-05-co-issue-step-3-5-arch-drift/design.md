## Context

`skills/co-issue/SKILL.md` は Phase 1 冒頭で architecture context（vision.md, context-map.md, glossary.md）を DCI で注入し、Step 1.5 で glossary 照合（未定義用語の INFO 通知）を実行する。これらは architecture spec → co-issue の一方向フロー。

本変更は逆方向（co-issue → architecture spec）のフィードバックとして Step 3.5 を追加する。architecture-spec-dci.md の「Step 3.5: Architecture Drift Detection」仕様に準拠する。

co-issue は Non-implementation controller のため、architecture spec を直接更新しない。検出と提案のみを行う。

## Goals / Non-Goals

**Goals:**
- `co-issue/SKILL.md` の Phase 3 完了後・Phase 4 前に Step 3.5 を追加
- 3 層シグナル検出の実装（明示的・構造的・ヒューリスティック）
- `deps.yaml` の co-issue 参照ファイル更新

**Non-Goals:**
- co-issue から architecture spec を直接更新する機能
- co-architect 自体の機能追加
- autopilot-retrospective の変更（別スコープ）
- worker-architecture の PR diff モード変更（別スコープ）

## Decisions

### 1. Step 3.5 の挿入位置: TaskUpdate Phase 3 → completed の直後

Phase 3 の specialist レビュー結果（findings テーブル）をユーザーに提示した後、Phase 4 の一括作成前に実行する。CRITICAL ブロック時は Step 3.5 を実行しない（Phase 4 ブロック中のため）。

### 2. architecture/ 非存在チェックを Step 3.5 の最初に配置

`architecture/domain/glossary.md` が存在しない場合は Step 3.5 全体をスキップし、出力なしで Phase 4 に進む。Step 1.5 と同じパターン。

### 3. 3 シグナルの優先評価順: 明示的 → 構造的 → ヒューリスティック

シグナルが 1 件でも検出されたら INFO 出力を行う。ただし全シグナルを評価して結果を集約してから出力する（早期リターンなし）。

### 4. 構造的シグナル検出: MUST 用語照合 + architecture/ ファイル名照合

- glossary.md の MUST 用語（不変条件・Entity・Workflow 等）が Issue body で言及されているか確認
- `architecture/` 配下のファイル名（contexts/*.md 等）が Issue body で参照されているか確認
- どちらかが 1 件以上 → 構造的シグナルあり

### 5. ヒューリスティック判定: ctx/* ラベル >= 3

specialist レビュー後の Issue candidate に付与された ctx/* ラベルを参照（structured_issue の recommended_labels）。ctx/* ラベルが 3 つ以上の Issue が 1 件以上あれば → ヒューリスティックシグナルあり。

### 6. 出力フォーマット: architecture-spec-dci.md の定義に準拠

```
[INFO] 以下の Issue が architecture spec に影響する可能性があります:
  "<タイトル>": explicit reference (architecture/...)
  "<タイトル>": invariant change (不変条件B)
architecture spec の事前更新を検討してください: /twl:co-architect
```

### 7. CRITICAL ブロック中は Step 3.5 をスキップ

Phase 3c でブロックが発生した場合、Phase 4 自体がスキップされる。Step 3.5 も同様にスキップし、「修正後に再実行してください」のメッセージのみ表示。

## Risks / Trade-offs

- **構造的シグナルの偽陽性**: glossary MUST 用語（例: "Workflow"）が一般的な文脈で使われた場合も検出される。INFO レベル・非ブロッキングのため許容
- **ヒューリスティックの粗さ**: ctx/* ラベル 3 件は経験則。閾値の妥当性は運用後に調整可能
- **architecture/ 未存在プロジェクトへの影響**: 存在チェックによりスキップ、影響なし
