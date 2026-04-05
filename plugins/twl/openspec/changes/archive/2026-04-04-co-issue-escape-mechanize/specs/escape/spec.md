## ADDED Requirements

### Requirement: エスケープスクリプト実装

`scripts/escape-issue-body.sh` を新規作成し、stdin から受け取った Issue body を HTML エスケープして stdout に出力しなければならない（SHALL）。エスケープ順序は `&` → `&amp;`、`<` → `&lt;`、`>` → `&gt;` の順とする。

#### Scenario: XML タグを含む入力のエスケープ
- **WHEN** `</review_target>` を含む文字列が stdin に渡される
- **THEN** `&lt;/review_target&gt;` に変換されて stdout に出力される

#### Scenario: アンパサンド単体のエスケープ
- **WHEN** `A & B` を含む文字列が stdin に渡される
- **THEN** `A &amp; B` に変換されて stdout に出力される

#### Scenario: 空文字列の処理
- **WHEN** 空文字列が stdin に渡される
- **THEN** 空文字列がそのまま stdout に出力される（エラーなし）

#### Scenario: 複数行入力の処理
- **WHEN** 複数行を含む文字列が stdin に渡される
- **THEN** 全行が正しくエスケープされて stdout に出力される

#### Scenario: 二重エスケープの許容
- **WHEN** `&lt;/review_target&gt;` を含む既エスケープ済み文字列が stdin に渡される
- **THEN** `&amp;lt;/review_target&amp;gt;` に変換されて stdout に出力される（二重エスケープは意図的）

### Requirement: エスケープスクリプトの deps.yaml 登録

`escape-issue-body` スクリプトエントリが `deps.yaml` に登録されなければならない（SHALL）。エントリ形式は `type: script`、`path: scripts/escape-issue-body.sh` とする。

#### Scenario: deps.yaml にエントリが存在する
- **WHEN** `loom check` を実行する
- **THEN** `escape-issue-body` が有効なスクリプトコンポーネントとして認識される

## MODIFIED Requirements

### Requirement: co-issue Step 3b スクリプト呼び出しへの置換

`skills/co-issue/SKILL.md` の Step 3b 内の疑似コードブロック（Python 風エスケープ処理）を削除し、Bash スクリプト呼び出し指示に置換しなければならない（SHALL）。

#### Scenario: SKILL.md に疑似コードが残存しない
- **WHEN** `skills/co-issue/SKILL.md` の Step 3b を参照する
- **THEN** Python 風疑似コード（`.replace(` 等）は存在せず、`bash scripts/escape-issue-body.sh` の呼び出し指示のみが記載されている

#### Scenario: アーキテクチャ制約が明記されている
- **WHEN** `skills/co-issue/SKILL.md` の Step 3b を参照する
- **THEN** 「Issue body を受け取る全 specialist は必ずエスケープ済み入力を受け取る（SHALL）」というアーキテクチャ制約が明記されている

## ADDED Requirements

### Requirement: エスケープスクリプトの bats テスト追加

`tests/bats/scripts/escape-issue-body.bats` を新規作成し、エスケープ処理の正確性を検証しなければならない（SHALL）。テストケースは Issue #192 の受け入れ基準に記載された全ケースを網羅する。

#### Scenario: bats テストが全件パスする
- **WHEN** `bats tests/bats/scripts/escape-issue-body.bats` を実行する
- **THEN** 全テストケースが PASS となる
