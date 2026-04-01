## ADDED Requirements

### Requirement: Cross-plugin 参照構文の定義

deps.yaml の calls 内で `plugin:component` 形式により他 plugin のコンポーネントを参照できなければならない（SHALL）。コロン `:` を含む calls 値は cross-plugin 参照として解釈しなければならない（MUST）。

#### Scenario: 正常な cross-plugin 参照のパース
- **WHEN** deps.yaml の calls に `atomic: "session:session-state"` が記述されている
- **THEN** loom はこれを session plugin の session-state コンポーネントへの cross-plugin 参照として認識する

#### Scenario: コロンなしの値は従来通りローカル参照
- **WHEN** deps.yaml の calls に `atomic: "my-command"` が記述されている
- **THEN** loom はこれを同一 plugin 内のコンポーネントへのローカル参照として処理する

### Requirement: Cross-plugin 参照の validate 検証

`loom validate` は cross-plugin 参照について、参照先 plugin の deps.yaml を読み込み、型整合性を検証しなければならない（MUST）。参照先 plugin が見つからない場合は warning を出力してスキップしなければならない（SHALL）。

#### Scenario: 参照先の型整合性が正しい場合
- **WHEN** caller が atomic 型で、cross-plugin 参照先が script 型である
- **THEN** validate は型違反を報告しない（atomic.can_spawn に script が含まれるため）

#### Scenario: 参照先の型整合性が不正な場合
- **WHEN** caller が specialist 型で、cross-plugin 参照先が workflow 型である
- **THEN** validate は型違反を報告する（specialist.can_spawn は空集合のため）

#### Scenario: 参照先 plugin が見つからない場合
- **WHEN** cross-plugin 参照の plugin 名に対応する deps.yaml が存在しない
- **THEN** validate は warning を出力し、該当の参照をスキップする（error にはしない）

### Requirement: Cross-plugin 参照の check 検証

`loom check` は cross-plugin 参照先のファイル存在を検証しなければならない（MUST）。参照先 plugin が見つからない場合は warning を出力してスキップしなければならない（SHALL）。

#### Scenario: 参照先ファイルが存在する場合
- **WHEN** cross-plugin 参照先のコンポーネントに path が定義されており、そのファイルが存在する
- **THEN** check は ok を報告する

#### Scenario: 参照先ファイルが存在しない場合
- **WHEN** cross-plugin 参照先のコンポーネントに path が定義されており、そのファイルが存在しない
- **THEN** check は missing を報告する

#### Scenario: 参照先 plugin が見つからない場合
- **WHEN** cross-plugin 参照の plugin 名に対応する deps.yaml が存在しない
- **THEN** check は warning を出力し、該当の参照をスキップする

## MODIFIED Requirements

### Requirement: script 型の can_spawn 拡張

types.yaml の script 型は `can_spawn: [script]` を持たなければならない（MUST）。これにより script→script の呼び出しが型ルール上で許可される。

#### Scenario: script が script を呼び出す場合
- **WHEN** script 型のコンポーネントが calls で別の script 型コンポーネントを参照している
- **THEN** validate は型違反を報告しない

#### Scenario: script が script 以外を呼び出す場合
- **WHEN** script 型のコンポーネントが calls で atomic 型コンポーネントを参照している
- **THEN** validate は型違反を報告する（script.can_spawn に atomic は含まれないため）
