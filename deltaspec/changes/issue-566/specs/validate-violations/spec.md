## MODIFIED Requirements

### Requirement: controller 型の spawnable_by/can_spawn 拡張

`types.yaml` の controller 型は、supervisor 型（su-observer 等）からの spawn を許可しなければならない（SHALL）。また controller 型は controller 型を spawn できなければならない（SHALL）。これにより ADR-014 で定義された su-observer ベースの自律監視アーキテクチャと整合する。

#### Scenario: su-observer が controller を spawn する宣言の検証

- **WHEN** `spawnable_by: [su-observer]` を宣言する controller 型コンポーネント（例: co-autopilot）が `twl --validate` で検証される
- **THEN** 違反なし（Violations: 0 相当）で通過する

#### Scenario: controller が controller を spawn する宣言の検証

- **WHEN** `can_spawn: [controller]` を宣言する controller 型コンポーネントが `twl --validate` で検証される
- **THEN** 違反なし（Violations: 0 相当）で通過する

### Requirement: atomic 型の spawnable_by/can_spawn 拡張

`types.yaml` の atomic 型は、user から直接 spawn されることを許可しなければならない（SHALL）。また atomic 型は atomic 型を spawn できなければならない（SHALL）。これにより su-compact が externalize-state を直接呼び出す既存設計と整合する。

#### Scenario: user が atomic を spawn する宣言の検証

- **WHEN** `spawnable_by: [user]` を宣言する atomic 型コンポーネント（例: su-compact, externalize-state）が `twl --validate` で検証される
- **THEN** 違反なし（Violations: 0 相当）で通過する

#### Scenario: atomic が atomic を spawn する宣言の検証

- **WHEN** atomic 型コンポーネントが atomic 型コンポーネントへの spawn edge を宣言している場合に `twl --validate` で検証される
- **THEN** edge 違反なし（Violations: 0 相当）で通過する

### Requirement: v3-calls-key チェックの plugin キー除外

`validate.py` の v3-calls-key バリデーターは、calls エントリの `plugin` キーを不明キーとして報告してはならない（SHALL NOT）。`plugin` はクロスプラグイン参照のメタ情報として正規の calls キーである。

#### Scenario: plugin キーを持つ calls エントリの検証

- **WHEN** `calls` エントリに `plugin: <name>` キーが含まれるスクリプト（例: spec-review-orchestrator, issue-lifecycle-orchestrator）が `twl --validate` で検証される
- **THEN** v3-calls-key 違反が報告されない

### Requirement: chain-steps.sh のステップ名統一

`chain-steps.sh` は deps.yaml の chain 定義で使用されているステップ名 `project-board-status-update` と一致しなければならない（SHALL）。`board-status-update` というエイリアスで登録してはならない（SHALL NOT）。

#### Scenario: chain-step-sync チェックでの一致確認

- **WHEN** `twl --validate` の chain-step-sync チェックが実行される
- **THEN** `board-status-update` に関する名前不一致違反が報告されない

## ADDED Requirements

### Requirement: validate 結果の 0 件違反

上記 4 つの修正が完了した後、`twl --validate` はゼロ件の違反を返さなければならない（SHALL）。

#### Scenario: 全修正後の validate 実行

- **WHEN** types.yaml・validate.py・chain-steps.sh の全修正が適用された状態で `twl --validate` が実行される
- **THEN** `Violations: 0` が出力される
