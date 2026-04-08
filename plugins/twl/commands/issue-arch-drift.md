---
type: atomic
tools: [Bash, Skill, Read]
effort: low
maxTurns: 10
---
# /twl:issue-arch-drift - Architecture Drift Detection

Issue candidate 群に対して architecture spec との乖離を 3 シグナルで評価する。非ブロッキング INFO 通知。

## 入力

- `issue_candidates`: Phase 3a で構造化された Issue candidate リスト（escaped_body, recommended_labels を含む）

## スキップ条件（いずれかで出力なし終了）

- `architecture/domain/glossary.md` が存在しない
- 呼び出し元で 1 件以上の Issue が CRITICAL ブロック状態にある

## フロー（MUST）

### シグナル 1: 明示的（explicit）

各 Issue candidate の body で `<!-- arch-ref-start -->` タグを検索し、`<!-- arch-ref-end -->` との間に記載されたパスを抽出する。`..` を含むパスは除外して警告（`⚠️ 不正パス: <path>`）を表示する。有効なパスが 1 件以上あれば明示的シグナルとして記録する。

### シグナル 2: 構造的（structural）

1. `architecture/domain/glossary.md` の `### MUST 用語` セクションのテーブルから用語名（列1）を抽出する
2. `architecture/` 配下のファイルパス一覧（`contexts/*.md` 等）を取得する
3. 各 Issue candidate の body で、MUST 用語またはファイル名パターンが**完全一致**するか確認する（部分一致・略語・表記ゆれは除外）
4. 1 件以上一致すれば構造的シグナルとして記録する（一致した用語/ファイルも記録）

### シグナル 3: ヒューリスティック（heuristic）

各 Issue candidate の recommended_labels に含まれる ctx/* ラベルの数を Issue 単位でカウントする。**ctx/* ラベルが 3 件以上の Issue candidate が 1 件以上存在する**場合、ヒューリスティックシグナルとして記録する。

### 出力

全シグナルを評価後に集約する（早期リターンなし）。シグナルが 1 件以上検出された場合のみ以下を出力する:

```
[INFO] 以下の Issue が architecture spec に影響する可能性があります:
  "<タイトル>": explicit reference (architecture/...)
  "<タイトル>": invariant change (<用語>)
  "<タイトル>": cross-context impact (ctx/* labels: N)
architecture spec の事前更新を検討してください: /twl:co-architect
```

シグナルが 0 件の場合は出力なしで呼び出し元に制御を返す。**非ブロッキング**: 出力後にユーザー入力を待たず Phase 4 に進む（MUST）。
