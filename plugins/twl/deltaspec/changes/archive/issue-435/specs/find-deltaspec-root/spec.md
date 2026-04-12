## MODIFIED Requirements

### Requirement: config.yaml マーカーベース検出

`find_deltaspec_root()` は `deltaspec/config.yaml` が存在するディレクトリのみを有効な DeltaSpec root として認識しなければならない（SHALL）。config.yaml を持たない `deltaspec/` ディレクトリはスキップしなければならない（SHALL）。

#### Scenario: config.yaml なし deltaspec/ のスキップ
- **WHEN** cwd の上位パスに `deltaspec/`（config.yaml なし）が存在し、さらに上位に `deltaspec/config.yaml` が存在する場合
- **THEN** config.yaml を持つ上位の deltaspec/ を返す

#### Scenario: walk-down fallback
- **WHEN** walk-up で config.yaml を持つ `deltaspec/` が見つからず、git toplevel 配下に `**/deltaspec/config.yaml`（maxdepth=3）が存在する場合
- **THEN** cwd に最も近い（最長共通パス）deltaspec root を返す

#### Scenario: 複数ヒット時の選択
- **WHEN** walk-down で複数の `deltaspec/config.yaml` が発見される場合
- **THEN** cwd との共通パスが最長のものを返す

#### Scenario: 検出失敗
- **WHEN** walk-up および walk-down のいずれでも config.yaml を持つ deltaspec/ が見つからない場合
- **THEN** `DeltaspecNotFoundError` を raise する

## ADDED Requirements

### Requirement: twl spec new の config.yaml 自動生成

`twl spec new` は `deltaspec/` を新規作成する際に `config.yaml` を自動生成しなければならない（SHALL）。既存の `deltaspec/config.yaml` が存在する場合は上書きしてはならない（MUST NOT）。

#### Scenario: 新規 deltaspec 作成時の config.yaml 生成
- **WHEN** `twl spec new <name>` 実行時に `deltaspec/` が存在しない場合
- **THEN** `deltaspec/config.yaml` を schema と context フィールド付きで自動生成し、`deltaspec/changes/<name>/` を作成する

#### Scenario: 既存 deltaspec への config.yaml 非上書き
- **WHEN** `twl spec new <name>` 実行時に `deltaspec/config.yaml` が既に存在する場合
- **THEN** config.yaml を変更せず、`deltaspec/changes/<name>/` のみ作成する
