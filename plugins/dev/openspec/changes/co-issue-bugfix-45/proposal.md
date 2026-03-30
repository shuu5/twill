## Why

co-issue ワークフロー実行時に、Issue 作成後の後処理チェーンが複数箇所で断絶している。
project-board-sync が誤った Project に同期し、ctx/* ラベルが自動付与されず、Project Board の Context フィールドが空のままになる。

## What Changes

- **project-board-sync**: Project 検出ロジックをリポジトリ名マッチング優先に改善
- **co-issue**: Phase 3→4 間で issue-structure の推奨ラベルを抽出し issue-create に受け渡すフロー追加
- **issue-create**: --label 引数の受け渡しドキュメントを明確化（既に対応済み、呼び出し側の問題）
- **project-board-sync**: ctx/* ラベルなし時の Context フィールド推定フォールバック追加

## Capabilities

### New Capabilities

- ctx/* ラベルの自動付与: issue-structure → co-issue → issue-create の推奨ラベル受け渡しチェーン
- Context フィールドのフォールバック推定: ctx/* ラベルがない場合、Issue タイトル・本文から Context を推定

### Modified Capabilities

- project-board-sync の Project 検出: 複数 Project 検出時にリポジトリ名と Project タイトルのマッチングを優先
- co-issue Phase 4: issue-structure 出力からの推奨ラベル抽出・issue-create への受け渡し

## Impact

- **変更対象ファイル**:
  - `skills/co-issue/SKILL.md`: Phase 3→4 間のラベル受け渡しフロー追加（~10行）
  - `commands/project-board-sync.md`: Project 判定改善 + Context フォールバック（~20行）
- **影響範囲**: co-issue ワークフローのみ。他のコントローラや既存の issue-create / issue-structure の外部インタフェースに変更なし
- **リスク**: 低。既存の正常パス（ctx/* ラベルあり + 単一 Project）には影響しない
