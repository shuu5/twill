## ADDED Requirements

### Requirement: loom-validate コンポーネント移植

既存 dev plugin から loom-validate を loom-plugin-dev に移植しなければならない（SHALL）。

対象コンポーネント:
- loom-validate: 構造・型ルール検証（loom + plugin validate）

#### Scenario: loom-validate の deps.yaml 登録
- **WHEN** loom-validate が移植された
- **THEN** deps.yaml の commands セクションに type: atomic で定義されている

#### Scenario: loom-validate のファイル配置
- **WHEN** loom-validate のプロンプトファイルが作成された
- **THEN** commands/loom-validate.md の形式で配置されている

### Requirement: 全体整合性検証

全48コンポーネント移植完了後、loom validate が PASS しなければならない（MUST）。

#### Scenario: loom validate の実行
- **WHEN** 全48コンポーネントが deps.yaml に定義され、プロンプトファイルが配置された
- **THEN** `loom check` コマンドが 0 エラーで完了する

#### Scenario: section 違反 0 件
- **WHEN** loom validate を実行した
- **THEN** section 違反（atomic が skills/ に配置等）が 0 件である

### Requirement: body 内参照の新命名規則合致

移植されたコンポーネントの body 内で他コンポーネントを参照する箇所は、loom-plugin-dev の命名規則に合致しなければならない（MUST）。

#### Scenario: controller 参照の更新
- **WHEN** body 内に `controller-autopilot`, `controller-issue` 等の旧名参照がある
- **THEN** `co-autopilot`, `co-issue` 等の新名に変換されている

#### Scenario: スキル呼び出しの形式
- **WHEN** body 内に Skill tool 呼び出しがある
- **THEN** `dev:<component-name>` の形式で参照されている
