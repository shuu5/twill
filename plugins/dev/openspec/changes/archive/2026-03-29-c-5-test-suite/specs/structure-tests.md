## ADDED Requirements

### Requirement: deps.yaml 構造バリデーション

deps.yaml v3.0 の構造が型ルール・参照整合性を満たすことをテストしなければならない（SHALL）。

#### Scenario: 必須フィールドの存在
- **WHEN** deps.yaml を解析する
- **THEN** version、plugin、entry_points フィールドが存在する

#### Scenario: entry_points のファイル存在
- **WHEN** deps.yaml の entry_points を列挙する
- **THEN** 各パスが実ファイルとして存在する

#### Scenario: コンポーネント path の実ファイル存在
- **WHEN** deps.yaml の全コンポーネントの path を列挙する
- **THEN** 各パスが実ファイルとして存在する

#### Scenario: calls 参照の解決
- **WHEN** 各コンポーネントの calls を列挙する
- **THEN** 各参照先が deps.yaml 内に定義されている

### Requirement: chain 定義の整合性テスト

deps.yaml の chains 定義が正しいステップ参照を持つことをテストしなければならない（MUST）。

#### Scenario: chain ステップの参照解決
- **WHEN** chains の各ステップ名を列挙する
- **THEN** 各ステップ名が deps.yaml 内の atomic/composite コンポーネントとして存在する

#### Scenario: chain type の有効性
- **WHEN** chains の各 type を確認する
- **THEN** 全て "A" または "B" である

### Requirement: テストランナー統合

run-tests.sh が bats テストと既存 scenarios テストの両方を実行し、統合結果を返すことをテストしなければならない（SHALL）。

#### Scenario: bats テスト実行
- **WHEN** `bash tests/run-tests.sh` を実行する
- **THEN** tests/bats/ 配下の .bats ファイルが bats-core で実行される

#### Scenario: 既存 scenarios 実行
- **WHEN** `bash tests/run-tests.sh` を実行する
- **THEN** tests/scenarios/ 配下の .test.sh ファイルも実行される

#### Scenario: 統合終了コード
- **WHEN** bats テストが全 pass、scenarios テストが全 pass の場合
- **THEN** run-tests.sh が終了コード 0 を返す
