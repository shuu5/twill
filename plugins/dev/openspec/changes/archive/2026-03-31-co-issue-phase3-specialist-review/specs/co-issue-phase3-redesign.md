## MODIFIED Requirements

### Requirement: co-issue Phase 3 を specialist 並列レビューに再構成

co-issue の Phase 3 フローを以下の順序に変更しなければならない（SHALL）:

1. 各 Issue 候補に対して issue-structure（テンプレート適用）と推奨ラベル抽出を実行
2. 全 Issue 構造化完了後、全 Issue × 2 specialist（issue-critic, issue-feasibility）を一括並列 spawn
3. 全 specialist 完了後、結果を集約しユーザーに提示
4. CRITICAL findings（confidence >= 80）がある Issue は修正必須

issue-dig と issue-assess の呼び出しを廃止しなければならない（MUST）。

#### Scenario: 通常の Phase 3 実行
- **WHEN** co-issue が Phase 3 に到達し、3 件の Issue 候補がある
- **THEN** 3 × issue-structure を順次実行後、6 agent（3 × issue-critic + 3 × issue-feasibility）を単一メッセージで一括並列 spawn する

#### Scenario: CRITICAL findings によるブロック
- **WHEN** issue-critic が severity: CRITICAL, confidence: 85 の finding を出力する
- **THEN** 当該 Issue は Phase 4（作成）に進めず、ユーザーに修正を求める

#### Scenario: WARNING のみの場合
- **WHEN** 全 specialist の findings が WARNING 以下のみ
- **THEN** findings をユーザーに提示し、Phase 4 への進行を許可する

#### Scenario: split 提案の適用
- **WHEN** specialist が scope category で split を提案し、ユーザーが承認する
- **THEN** Issue を分割するが、分割後の新 Issue に対して specialist 再レビューは行わない（最大 1 ラウンド）

### Requirement: --quick フラグ対応

`--quick` フラグが指定された場合、specialist 並列レビューをスキップしなければならない（SHALL）。issue-structure のみで Phase 3 を完了する。

#### Scenario: --quick 指定時
- **WHEN** co-issue が `--quick` フラグ付きで実行される
- **THEN** Phase 3 は issue-structure + 推奨ラベル抽出のみを実行し、specialist spawn をスキップする

## REMOVED Requirements

### Requirement: issue-dig 廃止

issue-dig コマンドを Phase 3 から削除しなければならない（SHALL）。`commands/issue-dig.md` を削除し、deps.yaml から `issue-dig` エントリを削除する。

#### Scenario: issue-dig が呼ばれないこと
- **WHEN** co-issue Phase 3 が実行される
- **THEN** issue-dig は呼び出されない

### Requirement: issue-assess 廃止

issue-assess コマンドを Phase 3 から削除しなければならない（SHALL）。`commands/issue-assess.md` を削除し、deps.yaml から `issue-assess` エントリを削除する。

#### Scenario: issue-assess が呼ばれないこと
- **WHEN** co-issue Phase 3 が実行される
- **THEN** issue-assess は呼び出されない
