# ADR-006: Project Board 必須化

## Status
Accepted

## Context

初期の plugins/twl では Project Board は optional だった。しかし運用を通じて以下の問題が顕在化した:

- autopilot が Issue 選択時に `gh issue list` を使用すると、単一リポの Issue しか取得できない
- 複数リポにまたがる twill-ecosystem では、Issue の優先順位やステータスがリポ横断で管理できない
- Issue のステータス（Todo/In Progress/Done）がローカル状態ファイルと乖離するリスク
- `gh issue list` のデフォルト件数制限が不足する大規模プロジェクト

## Decision

全プロジェクトで GitHub Projects V2 を必須とし、以下のルールを適用する:

### Board = Issue ステータスの SSOT

- autopilot の Issue 選択は `gh project item-list` で Status=Todo をクエリ
- Issue 完了時は issue-{N}.json の status=done と同時に Board ステータスを同期
- `gh issue list` は単一リポ専用のため、Board クエリには使用しない

### project-create 自動化

- `co-project create` 時に Project V2 を自動作成しリポジトリをリンク
- 既存プロジェクトは `co-project migrate` で Board をセットアップ

### 二層構造

```
ローカル (即時性)                Project Board (永続化・可視化)
issue-{N}.json  ─── 同期 ───>  GitHub Projects V2
session.json                    (SSOT for Issue status)
```

- ローカル状態ファイルは即時性を確保（10秒ポーリングで参照）
- Board は永続化・可視化を担当（人間の確認用、クロスリポ統合）
- **同期失敗は WARNING のみ**: Board 同期失敗で autopilot をブロックしない

### クエリ時の --limit 200 必須

Board クエリは `--limit 200` を明示指定する（デフォルト件数は不足する場合がある）。

## Consequences

### Positive
- Issue ステータスのクロスリポ可視化
- autopilot の Issue 選択が Board ベースで一貫
- 人間がブラウザから進捗を確認可能

### Negative
- `gh project` API の学習コスト
- Board 同期のオーバーヘッド（gh API 呼び出し）
- user → organization フォールバックの複雑性

### Mitigations
- project-board-sync / project-board-status-update を atomic コマンドとして抽象化
- 同期失敗時は WARNING のみでフローを継続
