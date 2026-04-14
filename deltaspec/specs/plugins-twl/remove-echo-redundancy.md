## Requirements

### Requirement: Step 0 auto_init フローの echo 補完削除

`change-propose.md` の Step 0 auto_init フローにおいて、`twl spec new` が自動補完するフィールド（`name:`, `status:`, `issue:`）を手動で echo 書き込みする処理を削除しなければならない（SHALL）。

#### Scenario: twl spec new 呼出後に echo 補完が存在しない
- **WHEN** `change-propose.md` の Step 0 auto_init フローを参照する
- **THEN** `echo "name: ..." >> .deltaspec.yaml` および `echo "status: ..." >> .deltaspec.yaml` の行が存在しない

#### Scenario: twl spec new の自動補完を説明するコメントが存在する
- **WHEN** `change-propose.md` の Step 0 内の `twl spec new "issue-<N>"` 呼出直後を参照する
- **THEN** `twl spec new` が `issue 番号・name・status` を自動補完することを説明するコメントが存在する

### Requirement: .deltaspec.yaml への重複エントリ防止

`twl spec new "issue-<N>"` 実行後に `.deltaspec.yaml` に重複フィールドが生成されてはならない（MUST NOT）。

#### Scenario: issue-N 形式の change 作成後に .deltaspec.yaml が重複なし
- **WHEN** `change-propose.md` の Step 0 フローに従い `twl spec new "issue-<N>"` を実行する
- **THEN** `.deltaspec.yaml` に `name:`, `status:`, `issue:` が各 1 回のみ存在する
