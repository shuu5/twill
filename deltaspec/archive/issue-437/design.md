## Context

`cli/twl/deltaspec/changes/` には OpenSpec 時代に生成された 16 の active change ディレクトリと 1 つの archived change が残っている。これらは `.openspec.yaml`（`name`/`status` フィールドなし）を使用しており、`twl spec` コマンド群が `.deltaspec.yaml` のみを認識するため正しく処理できない。`twl spec list` や `twl spec archive` が機能するためには `.deltaspec.yaml` 形式が必要。全て実装済みであるため、変換後に archive する。

## Goals / Non-Goals

**Goals:**
- `cli/twl/deltaspec/changes/` 内全 `.openspec.yaml` を `.deltaspec.yaml` にリネーム（17 ファイル）
- `name`/`status` フィールドが欠けている場合に補完
- 16 active changes を `twl spec archive --yes` で archive
- archive 後 `twl spec list` がアクティブ change 0 件を返すこと

**Non-Goals:**
- `config.yaml` の変更（既に正しい形式）
- `cli/twl` の Python/bash コード変更
- `plugins/twl/deltaspec/` への影響
- OpenSpec フォーマットの仕様変更

## Decisions

**決定 1: bash スクリプトによる一括リネーム**
`for` ループで各ディレクトリを走査し `mv .openspec.yaml .deltaspec.yaml` を実行する。`sed -i` で `name`/`status` フィールドを末尾追加する。Python や追加ツールは不要。

**決定 2: archive は `twl spec archive` CLI を使用**
独自スクリプトでファイル移動するのではなく、`twl spec archive --yes` を使う。CLI が specs 統合ロジック（`_integrate_specs`）を内包しているため整合性が保たれる。

**決定 3: archive は change 単位で逐次実行**
`twl spec list --json` でアクティブ change を取得し、1 件ずつ `twl spec archive` する。一括実行でコンフリクトが出た場合に個別対応可能にする。

## Risks / Trade-offs

- specs/ サブディレクトリを持つ changes が複数ある場合、`_integrate_specs` で統合コンフリクトが発生する可能性がある。その場合は手動レビューが必要。
- `.openspec.yaml` に独自フィールドが含まれる場合でも、そのままリネームするため既存フィールドは保持される（破壊なし）。
