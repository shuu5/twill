## ADDED Requirements

### Requirement: baseline-bash.md の新規作成

`plugins/twl/refs/baseline-bash.md` が存在し、bash スクリプト品質基準を 4 セクションで定義しなければならない（SHALL）。frontmatter は既存 baseline ファイルと同一形式（name, description, type: reference, disable-model-invocation: true）でなければならない（SHALL）。

#### Scenario: baseline-bash.md の存在確認
- **WHEN** `plugins/twl/refs/` ディレクトリを確認する
- **THEN** `baseline-bash.md` が存在し、4 つの `##` セクション見出し（`## 1. Character Class のハイフン配置` / `## 2. for-loop 変数の local 宣言` / `## 3. local 宣言の set -u 初期化` / `## 4. 環境変数パースの IFS 問題`）を持つ

#### Scenario: frontmatter 形式の確認
- **WHEN** `baseline-bash.md` の frontmatter を確認する
- **THEN** `name`, `description`, `type: reference`, `disable-model-invocation: true` フィールドが存在する

#### Scenario: BAD/GOOD 対比の確認
- **WHEN** `baseline-bash.md` の各セクションを確認する
- **THEN** 各セクションに BAD/GOOD 対比のコードブロックが含まれる

#### Scenario: IFS セクションのキーワード確認
- **WHEN** `baseline-bash.md` の IFS セクション（`## 4.`）を確認する
- **THEN** `IFS=`、`key="${line%%=*}"`、`val="${line#*=}"` のキーワードが含まれる

## MODIFIED Requirements

### Requirement: worker-code-reviewer.md への参照追加

`plugins/twl/agents/worker-code-reviewer.md` の「Baseline 参照（MUST）」セクションの番号付きリストに、3 番目のエントリとして `**/refs/baseline-bash.md` への参照が追加されなければならない（SHALL）。

#### Scenario: Baseline 参照リストの確認
- **WHEN** `worker-code-reviewer.md` の Baseline 参照セクションを確認する
- **THEN** 番号付きリストの 3 番目に `**/refs/baseline-bash.md` を含むエントリが存在する

### Requirement: deps.yaml への baseline-bash エントリ追加

`plugins/twl/deps.yaml` の C-3 セクションに `baseline-bash` エントリ（type: reference）が追加されなければならない（SHALL）。`phase-review` および `merge-gate` の calls セクションに `- reference: baseline-bash` が `baseline-input-validation` エントリの直後に含まれなければならない（SHALL）。

#### Scenario: C-3 セクションへのエントリ追加確認
- **WHEN** `plugins/twl/deps.yaml` の C-3 セクションを確認する
- **THEN** `baseline-bash` エントリが `type: reference` で存在する

#### Scenario: phase-review calls への参照追加確認
- **WHEN** `plugins/twl/deps.yaml` の `phase-review` calls セクションを確認する
- **THEN** `- reference: baseline-bash` が `- reference: baseline-input-validation` の直後に存在する

#### Scenario: merge-gate calls への参照追加確認
- **WHEN** `plugins/twl/deps.yaml` の `merge-gate` calls セクションを確認する
- **THEN** `- reference: baseline-bash` が `- reference: baseline-input-validation` の直後に存在する

### Requirement: baseline-coding-style.md の IFS セクション置換

`plugins/twl/refs/baseline-coding-style.md` の Bash IFS セクション（L156-178）が `baseline-bash.md` への相互参照に置換されなければならない（SHALL）。

#### Scenario: IFS セクション置換確認
- **WHEN** `plugins/twl/refs/baseline-coding-style.md` の IFS セクションを確認する
- **THEN** 元の IFS 実装内容が `baseline-bash.md` への参照リンクノートに置換されている
