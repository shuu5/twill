## Name
Spec Management

## Key Entities

- **Change**: openspec/changes/<name>/ に対応。スキーマ（spec-driven）に基づく成果物群を持つ
- **Artifact**: Change 内の成果物単位（proposal, design, specs, tasks）。依存関係と完了状態を持つ
- **ArtifactStatus**: ready | blocked | done。依存する Artifact の完了状態から算出
- **Instruction**: Artifact 作成のための指示テキストとテンプレート。JSON 出力対応
- **SpecValidation**: delta spec の構文検証（delta headers, Requirement prefix, SHALL/MUST, Scenario blocks）

## Dependencies

- なし（独立した Context。他の Context とはデータ共有しない）
- 将来的に Plugin Structure と連携可能（spec の capability → deps.yaml のコンポーネントへのマッピング）

## Constraints

- openspec/ ディレクトリは cwd から上方探索で発見する（プロジェクトルートに依存しない）
- スキーマは現在 "spec-driven" のみ。.openspec.yaml の schema フィールドで識別
- Artifact 間の依存グラフ: proposal → design, specs（並列）→ tasks
- archive 時に specs/ 内の delta headers（ADDED/MODIFIED/REMOVED）を main specs に統合

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `twl spec new <name>` | 新しい Change ディレクトリを作成 |
| `twl spec status <name>` | Artifact の完了状態を表示（JSON 対応） |
| `twl spec list` | 全 Change の一覧表示（ソート・JSON 対応） |
| `twl spec archive <name>` | 完了した Change をアーカイブし、main specs に統合 |
| `twl spec validate [name]` | delta spec の構文検証（全件: --all） |
| `twl spec instructions <artifact> <name>` | Artifact 作成の指示とテンプレートを出力 |
