## ADDED Requirements

### Requirement: specialist-audit スクリプト登録

`plugins/twl/deps.yaml` の `scripts:` セクションに `specialist-audit` エントリが存在しなければならない（SHALL）。エントリは `type: script`、`path: scripts/specialist-audit.sh`、非空の `description` を持つ。

#### Scenario: specialist-audit エントリが存在する
- **WHEN** `grep -A4 "^  specialist-audit:$" plugins/twl/deps.yaml` を実行する
- **THEN** `path: scripts/specialist-audit.sh` を含む出力が返る

### Requirement: merge-gate-check-spawn への calls 追加

`plugins/twl/deps.yaml` の `merge-gate-check-spawn` エントリに `calls:` セクションが存在し、`specialist-audit` を含まなければならない（SHALL）。形式は既存 `merge-gate-cross-pr-ac` の `calls:\n  - script: <name>` に準拠する。

#### Scenario: merge-gate-check-spawn が specialist-audit を calls に持つ
- **WHEN** `sed -n '/^  merge-gate-check-spawn:$/,/^  [a-z-]\+:$/p' plugins/twl/deps.yaml | grep -A10 'calls:' | grep -q '- script: specialist-audit'` を実行する
- **THEN** exit 0 で成功する

## MODIFIED Requirements

### Requirement: twl check 通過

`twl check` が deps.yaml の未登録コンポーネント警告なしで exit 0 を返さなければならない（MUST）。`specialist-audit` 関連の未登録エラーが含まれてはならない。

#### Scenario: twl check が specialist-audit 関連警告なしで通過
- **WHEN** `twl check` を実行する
- **THEN** exit 0 を返し、`specialist-audit` に関連する ERROR/WARNING が出力されない

### Requirement: README.md 反映

`twl --update-readme` 実行後、`plugins/twl/README.md` に `specialist-audit` が登録済みコンポーネントとして含まれなければならない（SHALL）。

#### Scenario: README に specialist-audit が反映される
- **WHEN** `(cd plugins/twl && twl --update-readme)` を実行する
- **THEN** `plugins/twl/README.md` に `specialist-audit` が含まれる
