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

全シグナルを評価後に集約する（早期リターンなし）。シグナルが 1 件以上検出された場合のみ出力する。

#### WARNING シグナル（明示的/構造的）が 1 件以上存在する場合

```
[WARNING] 以下の Issue が architecture spec に影響する可能性があります:
  "<タイトル>": explicit reference (architecture/...)
  "<タイトル>": invariant change (<用語>)
architecture spec の事前更新を推奨します。今どうしますか？
  1. 今すぐ更新する（/twl:co-architect）
  2. 後で更新する（続行）
  3. スキップ（続行）
```

WARNING 時は **AskUserQuestion tool** でユーザーに確認する。選択肢: 「今すぐ更新する」「後で更新する」「スキップ」。「後で更新する」または「スキップ」が選択された場合は Phase 4 に進む（非ブロッキング）。

ヒューリスティックシグナルも同時に検出された場合は、WARNING 出力の後に続けて INFO として追記する:
```
  "<タイトル>": cross-context impact (ctx/* labels: N)  [INFO]
```

#### WARNING シグナルなし、ヒューリスティックのみの場合

```
[INFO] 以下の Issue が architecture spec に影響する可能性があります:
  "<タイトル>": cross-context impact (ctx/* labels: N)
architecture spec の事前更新を検討してください: /twl:co-architect
```

INFO 時はユーザー入力を待たず Phase 4 に進む（非ブロッキング）。

シグナルが 0 件の場合は出力なしで呼び出し元に制御を返す。
