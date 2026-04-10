# ADR-007: Cross-repo Project Management

## Status
Accepted

## Context

plugins/twl は twill CLI に依存しており、機能追加やバグ修正が両リポにまたがることがある。初期設計では各リポが独立した Issue 管理を行っていたが、以下の問題が発生した:

- twill 側の Issue 完了が plugins/twl 側のブロック解除に反映されるまでの手動追跡が煩雑
- 要望が複数リポにまたがる場合、どのリポに Issue を起票すべきか曖昧
- プロジェクト全体の進捗が一元的に把握できない

## Decision

### twill-ecosystem プロジェクト

GitHub Projects V2 の `twill-ecosystem`（#6, owner: shuu5）をクロスリポジトリ統合管理に使用する。

**リンク済みリポ**: twill

### co-issue のクロスリポ Issue 分割

co-issue の Phase 2（Step 2a）でクロスリポ横断を自動検出する:

1. explore-summary.md の内容から複数リポ言及を検出
2. 対象リポ一覧を **Project のリンク済みリポジトリから動的取得**（ハードコード禁止）
3. ユーザーに分割提案: [A] リポ単位で分割 / [B] 単一 Issue として作成
4. 分割時: parent Issue + リポ別子 Issue の構造で一括作成

### リポ一覧の動的取得

```bash
# Project にリンクされたリポジトリを GraphQL で取得
# project-board-status-update と同様の user → organization フォールバック
```

Project にリンクされていない場合、クロスリポ検出はスキップする（従来の単一リポ動作）。

### autopilot のクロスリポ対応

autopilot は **単一リポ内**で動作する。クロスリポ依存がある場合は:
- 子 Issue がリポ別に起票されるため、各リポの autopilot が独立して処理
- parent Issue は全子 Issue の完了で手動クローズ（または自動化は将来検討）

## Consequences

### Positive
- 要望の全体像が parent Issue で把握可能
- リポ別の実装スコープが明確
- Project Board でクロスリポ進捗を一覧

### Negative
- parent-child 構造の管理コスト
- クロスリポ依存の自動解決は未サポート（手動調整が必要）
- gh project API のフォールバック処理の複雑性

### Mitigations
- リポ一覧はハードコードせず動的取得で保守コストを最小化
- autopilot は単一リポ完結を維持し、クロスリポはユーザー判断に委ねる
