## Context

`workflow-issue-lifecycle` は co-issue v2 のコアワークフローであり、Issue の仕様レビュー（spec-review）を担う。現在、round loop 正常完了後に `refined` ラベルを付与するステップが欠落している。`refined` ラベルは autopilot が実装対象 Issue を選択する際の品質フィルタとして機能するため、付与漏れが発生すると品質保証済み Issue が実装キューに入らないという問題が生じる。

変更対象はプロンプトファイル（SKILL.md）のみであり、スクリプト・ライブラリへの変更は不要。

## Goals / Non-Goals

**Goals:**

- `workflow-issue-lifecycle` SKILL.md に Step 4.5 を追加し、round loop 正常完了時に `labels_hint` へ `"refined"` を追記する
- `quick_flag=true` または `circuit_broken` の場合はスキップする条件分岐を実装する
- bats テストに Step 4.5 の判定ロジックを検証するテストケースを追加する

**Non-Goals:**

- `issue-create.md` 側の変更（方法 B は非採用）
- `issue-cross-repo-create.md` の変更
- `scope/*` ラベルの自動付与（別 Issue 対応）
- `deltaspec/specs/issue-lifecycle.md` への Scenario 追加（別 Issue 対応）

## Decisions

**方法 A（workflow-issue-lifecycle 内で labels_hint に追加）を採用**

`issue-cross-repo-create.md` には `REFINED_LABEL_OK` フラグによる条件付き `refined` 付与ロジックが既に存在するが、通常の `issue-create.md` には同ロジックがない。方法 B（`issue-create.md` に追加）は `issue-cross-repo-create.md` との重複を生むため非採用。呼び出し側のワークフローで `labels_hint` に追記する方法 A が最も侵襲性が低い。

**Step 4.5 の挿入位置: Step 4（round loop）と Step 5（arch-drift）の間**

round loop の完了状態（`circuit_broken` フラグ）を判定した直後に `refined` を付与するため、Step 4 直後が最適な位置。

**ラベル冪等作成ロジック不要**

`gh issue create --label` は対象リポに存在しないラベルを指定した場合でもエラーにならず自動作成されるため、別途冪等作成ロジックは不要。`labels_hint` への追記のみで十分。

## Risks / Trade-offs

- `quick_flag` の判定は SKILL.md 内の変数参照に依存するため、変数名が変更された場合は追従が必要
- bats テストで SKILL.md 内のロジックを直接テストするのは構造的に困難なため、ロジック相当の Bash スニペットをテスト内に再現する形式を採用
