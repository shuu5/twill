## ADDED Requirements

### Requirement: validate_types で scripts セクションを検証する
validate_types 関数は scripts セクション内のコンポーネントに対して、セクション配置・can_spawn・spawnable_by・呼び出しエッジの4チェックを実行しなければならない（MUST）。

#### Scenario: script のセクション配置チェック
- **WHEN** scripts セクションに type=`script` のコンポーネントが定義されている
- **THEN** セクション配置チェックが OK となる（script 型の section は `scripts`）

#### Scenario: script の不正な呼び出しエッジ
- **WHEN** type=`controller` のコンポーネントが `{script: name}` を calls に持つ
- **THEN** edge チェックで violation が報告される（controller は script を can_spawn に含まない）

#### Scenario: script の正当な呼び出しエッジ
- **WHEN** type=`atomic` のコンポーネントが `{script: name}` を calls に持つ
- **THEN** edge チェックが OK となる（atomic は script を spawnable_by に含む… ではなく、atomic の can_spawn に script が必要）

### Requirement: validate_v3_schema で script キーを許可する
v3_type_keys セットに `script` を追加し、calls キーバリデーションで `script` を有効な型名キーとして扱わなければならない（SHALL）。

#### Scenario: v3.0 calls キー検証
- **WHEN** v3.0 deps.yaml のコンポーネントが `{script: name}` を calls に持つ
- **THEN** validate_v3_schema が violation を報告しない

### Requirement: 旧形式 scripts フィールドに WARNING を出す
v3.0 deps.yaml で、コンポーネントが `scripts:` フィールド（リスト型）を持つ場合、非推奨 WARNING を出さなければならない（MUST）。

#### Scenario: コンポーネント内の旧 scripts フィールド検出
- **WHEN** skills/commands/agents セクション内のコンポーネントが `scripts: [name.sh]` フィールドを持つ
- **THEN** validate_v3_schema が `[v3-legacy-scripts]` WARNING を報告する

#### Scenario: scripts フィールドがないコンポーネント
- **WHEN** コンポーネントに `scripts:` フィールドがない
- **THEN** WARNING は報告されない

## MODIFIED Requirements

### Requirement: deep_validate で script 型をスキップする
deep_validate 関数は script 型のコンポーネントに対して frontmatter-body ツール整合性チェックをスキップしなければならない（MUST）。

#### Scenario: script 型の tools チェックスキップ
- **WHEN** deep_validate が実行され、scripts セクションにコンポーネントが存在する
- **THEN** そのコンポーネントに対して frontmatter/tools 整合性チェックは実行されない

### Requirement: audit_report で script 型をスキップする
audit_report 関数は script 型のコンポーネントに対して Inline Implementation / Tools Accuracy / Self-Contained チェックをスキップしなければならない（MUST）。

#### Scenario: audit の script スキップ
- **WHEN** `twl --audit` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** Section 2 (Inline Implementation)、Section 4 (Tools Accuracy)、Section 5 (Self-Contained) の各テーブルに script コンポーネントの行が含まれない

### Requirement: validate_body_refs で script 型をスキップする
validate_body_refs 関数は scripts セクションのコンポーネントに対して body 内参照チェックをスキップしなければならない（SHALL）。

#### Scenario: script の body-ref スキップ
- **WHEN** validate_body_refs が実行される
- **THEN** scripts セクションのコンポーネントは走査対象に含まれない
