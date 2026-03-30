## Context

co-issue ワークフローは Phase 1-4 の 4 段階で Issue を作成する。Phase 3 の issue-structure が ctx/* ラベルを推奨出力するが、Phase 4 の co-issue がそれを解析せず issue-create に渡さないため、ラベルなしで Issue が作成される。その結果、後続の project-board-sync で Context フィールドが空になる。

また project-board-sync は複数 Project が検出された場合に「最初の Project を使用」するが、イテレーション順序が不定のため誤った Project に同期する。

## Goals / Non-Goals

**Goals:**

- co-issue の推奨ラベル受け渡しチェーンを修復する
- project-board-sync の Project 検出をリポジトリ名マッチングで確実にする
- ctx/* ラベルがない場合の Context フィールドフォールバックを追加する

**Non-Goals:**

- co-issue 以外のコントローラ修正
- project-board-sync のフィールド自動作成
- issue-structure のラベル推奨ロジック自体の変更

## Decisions

### D1: co-issue Phase 4 でのラベル抽出方式

issue-structure の出力に含まれる `## 推奨ラベル` セクションから `ctx/<name>` を正規表現で抽出し、issue-create の `--label` 引数に渡す。

**根拠**: issue-structure の出力フォーマットは既に定義済み。co-issue 側で抽出ロジックを追加するだけで解決する。issue-structure / issue-create のインタフェースを変更する必要がない。

### D2: project-board-sync の Project 検出改善

現在のリポジトリ名（`nameWithOwner`）と Project タイトルのマッチングを追加。完全一致 > 部分一致 > フォールバック（最初）の優先順位で選択する。

**根拠**: 既存の GraphQL クエリで `repositories.nodes[].nameWithOwner` を取得済み。リポジトリ名マッチングは追加コストなしで実装可能。

### D3: Context フィールドのフォールバック推定

ctx/* ラベルなし時、architecture/ の context 一覧を取得し、Issue タイトル・本文とのキーワードマッチングで Context を推定する。推定結果は project-board-sync 内で直接適用する。

**根拠**: issue-structure Step 2.5 と同様のロジックだが、ラベル付与が漏れた既存 Issue にも対応するためproject-board-sync 側にもフォールバックを持たせる。

## Risks / Trade-offs

- **Context 推定の誤判定リスク**: フォールバック推定はキーワードマッチングに依存するため、曖昧な Issue では誤った Context が設定される可能性がある。ただしフォールバックであり、正規パス（ctx/* ラベルあり）には影響しない。
- **project-board-sync のタイトルマッチング**: Project タイトルがリポジトリ名と異なる場合にマッチしない。その場合は既存の「最初の Project」フォールバックが適用される。
