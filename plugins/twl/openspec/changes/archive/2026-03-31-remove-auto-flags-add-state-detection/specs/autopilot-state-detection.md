## ADDED Requirements

### Requirement: issue-{N}.json ベース autopilot 判定パターン

Worker 層コンポーネントは `state-read.sh --type issue --issue $ISSUE_NUM --field status` を使用して autopilot 配下かどうかを判定しなければならない（SHALL）。`--auto`/`--auto-merge` フラグによる判定を使用してはならない（MUST NOT）。

- `status=running` → autopilot 配下（自動継続）
- 空文字列（ファイル不在）→ standalone 実行（案内表示で停止）

#### Scenario: autopilot 配下での判定
- **WHEN** Worker が autopilot-launch 経由で起動され、`issue-{N}.json` が `status=running` で存在する
- **THEN** `state-read.sh` が `running` を返し、コンポーネントは自動継続モードで動作する

#### Scenario: standalone 実行での判定
- **WHEN** ユーザーが直接 `workflow-setup #47` を実行し、`issue-47.json` が存在しない
- **THEN** `state-read.sh` が空文字列を返し、コンポーネントは案内表示で停止する

## MODIFIED Requirements

### Requirement: workflow-setup の引数解析統一

`skills/workflow-setup/SKILL.md` の引数解析から `--auto` と `--auto-merge` を除去しなければならない（MUST）。chain 自動継続判定は state-read.sh に委譲しなければならない（SHALL）。

- Step 4（workflow-test-ready 遷移）: `--auto` 条件を IS_AUTOPILOT 判定に置換

#### Scenario: workflow-setup から --auto/--auto-merge 除去
- **WHEN** `skills/workflow-setup/SKILL.md` の引数解析セクションを確認する
- **THEN** `--auto` と `--auto-merge` への参照が存在しない。`#N` の Issue 番号解析のみ残る

#### Scenario: workflow-setup の自動継続判定
- **WHEN** autopilot 配下で workflow-setup が Step 4 に到達する
- **THEN** `state-read.sh` で `status=running` を確認し、自動的に `workflow-test-ready` を実行する

### Requirement: opsx-apply のフラグ除去

`commands/opsx-apply.md` から `--auto` モード分岐を除去しなければならない（MUST）。chain 自動継続は state-read.sh で判定しなければならない（SHALL）。

#### Scenario: opsx-apply から --auto 分岐除去
- **WHEN** `commands/opsx-apply.md` を確認する
- **THEN** `--auto` への参照が存在しない。Step 3 の分岐が IS_AUTOPILOT 判定に置換されている

#### Scenario: opsx-apply の自動継続
- **WHEN** autopilot 配下で opsx-apply が全タスク完了後に到達する
- **THEN** `state-read.sh` で判定し、自動的に `workflow-pr-cycle` を実行する

### Requirement: pr-cycle-analysis のフラグ除去

`commands/pr-cycle-analysis.md` から `--auto` 引数を除去しなければならない（MUST）。自動起票判定は state-read.sh で行わなければならない（SHALL）。

#### Scenario: pr-cycle-analysis から --auto 除去
- **WHEN** `commands/pr-cycle-analysis.md` の引数セクションを確認する
- **THEN** `--auto` が引数リストに存在しない

#### Scenario: autopilot 配下での自動起票
- **WHEN** autopilot 配下で信頼度 70 以上の Issue が検出される
- **THEN** `state-read.sh` で `status=running` を確認し、自動起票を実行する

### Requirement: self-improve-propose のフラグ除去

`commands/self-improve-propose.md` から `--auto` 引数を除去しなければならない（MUST）。自動承認判定は state-read.sh で行わなければならない（SHALL）。

#### Scenario: self-improve-propose から --auto 除去
- **WHEN** `commands/self-improve-propose.md` の引数セクションを確認する
- **THEN** `--auto` が引数リストに存在しない

#### Scenario: autopilot 配下での自動承認
- **WHEN** autopilot 配下で信頼度 70 以上の改善提案が存在する
- **THEN** `state-read.sh` で `status=running` を確認し、自動承認を実行する

### Requirement: autopilot-launch プロンプト変更

`commands/autopilot-launch.md` の Worker 起動プロンプトから `--auto --auto-merge` を除去し、Issue 番号のみを渡さなければならない（MUST）。

#### Scenario: autopilot-launch のプロンプト
- **WHEN** `commands/autopilot-launch.md` の Step 3 を確認する
- **THEN** PROMPT が `/twl:workflow-setup #${ISSUE}` である（`--auto --auto-merge` なし）

### Requirement: co-autopilot の --auto-merge 除去

`skills/co-autopilot/SKILL.md` から `--auto-merge` への全ての言及を除去しなければならない（MUST）。`--auto`（計画確認スキップ）は Pilot 層フラグとして存続する（SHALL）。

#### Scenario: co-autopilot から --auto-merge 言及除去
- **WHEN** `skills/co-autopilot/SKILL.md` を確認する
- **THEN** `--auto-merge` への参照が存在しない。`--auto` は存続している

## REMOVED Requirements

### Requirement: --auto-merge フラグの完全除去

`--auto-merge` フラグは全コンポーネントから除去されなければならない（MUST）。`--auto-merge` は独立して消費される箇所が皆無であり、完全に死んだフラグである。

#### Scenario: プロジェクト全体からの --auto-merge 除去
- **WHEN** 実装コード（commands/, skills/）内で `--auto-merge` を検索する
- **THEN** 一致するものが存在しない（openspec の過去 change/archive は対象外）
