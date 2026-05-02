---
name: twl:co-explore
description: |
  問題探索の独立コントローラー。ユーザーとの対話的探索を行い、
  explore-summary を .explore/<issue-number>/summary.md に保存。
  Issue リンクで co-issue / co-architect に接続する。

  Use when user: says 探索して/explore/問題を調べて/深堀りして,
  wants to explore a problem before creating issues.
type: controller
effort: medium
tools:
- Bash
- Read
- Write
- Grep
- Glob
spawnable_by:
- user
---

# co-explore

問題探索の独立コントローラー。explore-summary を出力して終了する純粋な探索ツール。

## 不変条件（MUST / MUST NOT）

- explore-summary を `.explore/<issue-number>/summary.md` に出力して終了する（MUST）
- ゼロ探索で summary を出力してはならない（MUST NOT）。最低 1 往復のユーザー対話を行うこと
- Phase 2 以降（Issue 精緻化・作成）を実行してはならない（MUST NOT）。それは co-issue の責務
- 対話的コントローラーである。AskUserQuestion を禁止する指示では起動できない（MUST）

## Step 0: 入力解析

`$ARGUMENTS` を解析する。

- **`#N` パターン検出時**: 既存 Issue `#N` に紐づく探索。`gh issue view N --json number,title,body` で取得し `ISSUE_NUMBER=N` に設定
- **`#N` なし + テキストあり**: 新規問題の探索。Step 1 で Issue draft を起票
- **引数なし**: 「何を探索しますか？」と AskUserQuestion で確認

## Step 1: Issue 確保

`ISSUE_NUMBER` が未設定（新規探索）の場合:

1. ユーザーの要望テキストから 1 行タイトルを生成
2. draft Issue を起票:
   ```bash
   ISSUE_NUMBER=$(gh issue create \
     --title "<タイトル>" \
     --body "co-explore による探索中。summary 完了後に更新予定。" \
     --label "exploration" \
     --json number -q '.number')
   ```
3. `ISSUE_NUMBER` を設定

既に `ISSUE_NUMBER` がある場合はスキップ。

## Step 2: 対話的探索

`architecture/` が存在する場合、vision.md・context-map.md・glossary.md を Read して `ARCH_CONTEXT` として保持（不在はスキップ）。

### 探索スタンス（explore.md から継承）

- **好奇心を持ち、指示的にならない**: ユーザーの要望を深堀りする質問を自然にする
- **忍耐強く結論を急がない**: 十分に議論してから summary へ
- **実地的にコードベースを探索**: Read/Grep/Glob で実際のコードを確認し、推測で語らない
- **可視化する**: ASCII 図でシステム構造・影響範囲を提示
- **前提を疑う**: ユーザーの前提も自分の前提も検証する

### 対話フロー

1. ユーザーの要望を確認（Issue body または起動引数から）
2. co-explore 自身が Read/Grep/Glob でコードベースを調査
3. 調査結果をユーザーに直接提示して議論:
   - 問題空間の明確化
   - 前提への質問
   - 影響範囲の可視化（ASCII 図）
   - 代替アプローチの提案
4. ユーザーの反応を受けてさらに深堀り（2-3 を繰り返し）

## Step 3: summary-gate

ユーザーとの対話が十分に行われた後、AI が explore-summary の内容を組み立てて提示する:

「以下の内容で explore-summary をまとめます:」
（summary 内容をテキストで表示）

AskUserQuestion で 3 択を提示:
- `[A] この summary で確定`
- `[B] summary を修正したい（具体的に指定してください）`
- `[C] explore-summary.md を手動編集したい`

**[A] 選択時**: Step 4 へ。

**[B] 選択時**: 修正して再提示 → summary-gate に戻る。

**[C] 選択時**:
- `.explore/<ISSUE_NUMBER>/summary.md` に現在の内容を書き出し、パスを提示
- edit-complete-gate（AskUserQuestion）:
  - `[A] 編集完了（再読み込みして続行）`
  - `[B] 編集をキャンセル（直前の summary で summary-gate に戻る）`

## Step 4: summary 保存 + Issue リンク

1. `.explore/<ISSUE_NUMBER>/summary.md` に explore-summary を書き出し
2. `twl explore-link set <ISSUE_NUMBER> .explore/<ISSUE_NUMBER>/summary.md` で Issue にコメント
3. 完了メッセージ:

```
>>> explore 完了: Issue #<N>

explore-summary: .explore/<N>/summary.md
Issue にリンク済み。

次のステップ:
  - Issue 精緻化: /twl:co-issue refine #<N>
  - 直接実装: /twl:co-autopilot #<N>
```

## プロンプト規約

- spawn-controller.sh が付与した provenance section を Issue body 末尾にコピーすること（MUST）

## 禁止事項（MUST NOT）

- Issue の精緻化・テンプレート適用・ラベル付与を行ってはならない（co-issue の責務）
- コードの実装を行ってはならない（探索モード。DeltaSpec 成果物の作成は許可）
- `.explore/` を git にコミットしてはならない
