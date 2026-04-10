## Context

autopilot ワークフローは通常、Issue の実装と DeltaSpec 作成を同一ブランチ内で行うことを前提としている。しかし「実装が別 PR でマージ済みであり、DeltaSpec のみを後付けで追加する」ケース（retroactive DeltaSpec）では、AC 達成証跡が本 PR の diff に含まれないため merge-gate が誤判定する問題がある。

## Goals / Non-Goals

**Goals:**
- retroactive DeltaSpec ケースを autopilot ワークフローで正式サポートする
- `implementation_pr` フィールドで実装 PR を追跡可能にする
- merge-gate が cross-PR AC 検証モードで正しく動作する

**Non-Goals:**
- 実装 PR のコードを再検証すること（マージ済みとして信頼する）
- 過去の全 Issue の retroactive 化

## Decisions

1. **`implementation_pr` フィールドの追加**: `issue-<N>.json` に `implementation_pr: <PR番号>` を追加。init 時に Issue body から `Implemented-in: #<N>` タグ、または PR コメントから自動検出する。

2. **`deltaspec_mode: retroactive` の追加**: mode フィールドで retroactive を識別。workflow-setup の init ステップでブランチの diff を解析し、実装コードが含まれない場合に自動設定する。

3. **merge-gate の cross-PR 検証**: `implementation_pr` が設定されている場合、AC 検証を本 PR diff ではなく参照 PR のマージコミットに対して実行する。`gh pr view <implementation_pr> --json mergeCommit` で commit SHA を取得し、`git show` で検証する。

4. **workflow-setup での retroactive 検出**: `git diff origin/main...HEAD -- '*.py' '*.sh' '*.ts'` で実装ファイルの変更がゼロかつ DeltaSpec ファイルのみの場合に retroactive として検出する。

## Risks / Trade-offs

- **`implementation_pr` の自動検出精度**: Issue body や PR コメントにタグがない場合は手動入力が必要になる。ユーザープロンプトで対応。
- **cross-PR 検証の複雑性**: merge-gate のロジックが複雑化する。ただし retroactive モードは例外ケースなので、シンプルな分岐（`implementation_pr` の有無）で管理する。
- **後方互換性**: 既存の `issue-<N>.json` に `implementation_pr` フィールドがない場合は通常モードとして動作するため、破壊的変更なし。
