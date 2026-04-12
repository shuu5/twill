## Context

twill plugin の gh 読み込み箇所は歴史的に body と comments を個別に取得しており、body のみで済ませている箇所が複数残っている。comments に蓄積された仕様・AC は workflow-issue-refine や autopilot から見えないため、判断品質を毀損している。共通ヘルパーを新設して全箇所を統一する。

`scripts/lib/` 配下には既に `pr-create-helper.sh` などのヘルパーが存在しており、`gh-read-content.sh` を同一ディレクトリに追加するのが自然な配置。

## Goals / Non-Goals

**Goals:**

- `gh_read_issue_full` / `gh_read_pr_full` を持つ共通ヘルパー `gh-read-content.sh` を新設する
- body + 全 comments を切り詰めなしで結合した単一テキストを返す
- `--repo <R>` オプションで cross-repo 対応
- エラー時は空文字列 + stderr 警告でグレースフルにフォールバック
- 既存 gap 6 箇所（B-1）と個別実装 2 箇所（B-2）を共通ヘルパー経由に統一
- `workflow-issue-refine` が Issue comments を specialist に注入できるようにする
- content-reading vs meta-only ポリシーをドキュメントと型ルールとして確立する

**Non-Goals:**

- GraphQL API への移行
- PR review comments（inline diff comments）の統合
- Comments のページング対応（gh CLI が自動で全件取得するため不要）
- meta-only 読み込み（state/labels/number/id/mergeCommit/files/title）の書き換え
- コメント本文の個別解析・構造化

## Decisions

**D-1: 単一ファイル `gh-read-content.sh` に Issue/PR 両関数を同居**

Issue と PR の取得パターンは対称的であり、別ファイルに分けると source の管理が煩雑になる。単一ファイルで `gh_read_issue_full` と `gh_read_pr_full` の両方を提供する。

**D-2: 出力フォーマット — body + separator + comments の平文結合**

```
<body>

## === Comments ===

<comment1>

---

<comment2>
```

LLM や grep の双方が解釈しやすい平文。JSON 構造化は不要（呼び出し側は全テキストを渡すだけでよい）。

**D-3: 切り詰めは呼び出し側の責任**

ヘルパー側での切り詰めは禁止。トークン制限への対応は呼び出しコンテキスト（LLM / スクリプト）の責任。

**D-4: `autopilot-multi-source-verdict.md` の切り詰め撤廃**

`[:1024]` および `[-5:]` による切り詰めは、長大な議論や古い制約が切れ落ちる根本原因。full content を渡し、必要に応じて呼び出し側で制御する。

**D-5: `workflow-issue-refine` への注入は `issue-spec-review.md` の `<review_target>` に追加**

`commands/issue-spec-review.md` の specialist prompt に `### === Issue Comments ===` セクションを追加する。`SKILL.md` の Step 3a で comments を取得して注入する。

**D-6: deps.yaml への追加は `lib` カテゴリ**

`scripts/lib/` 配下の既存ヘルパーの deps.yaml パターンに倣い、`lib` タイプで追加する。

## Risks / Trade-offs

- **トークン増大**: comments を全件取得するため、長い Issue/PR では LLM へのトークン入力が増大する。ただし autopilot-multi-source-verdict は既存でも body を全取得しており、コメント追加は許容範囲内とみなす。
- **`autopilot-plan.sh` の regression リスク**: B-2 の書き換えで `issue_touches_deps_yaml` の動作に regression が生じる可能性がある。BATS テストで事前・事後の動作を検証する。
- **`workflow-issue-refine` の specialist 呼び出し変更**: comments 注入により specialist の応答が変わる可能性があるが、より正確な refinement が期待されるため許容。
