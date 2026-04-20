## ADDED Requirements

### Requirement: specialist-audit BATS テスト追加

`plugins/twl/tests/bats/scripts/specialist-audit.bats` が存在し、5ケースをすべてカバーしなければならない（SHALL）。`bats plugins/twl/tests/bats/scripts/specialist-audit.bats` で全 PASS する。

#### Scenario: PASS ケース（expected ⊆ actual）
- **WHEN** expected が actual の部分集合であるケースで `specialist-audit.sh` を実行する
- **THEN** exit 0 を返し、JSON 出力の `.status` が `"PASS"` である

#### Scenario: FAIL ケース（warn-only モード）
- **WHEN** missing が非空かつ `--warn-only` フラグを指定して実行する
- **THEN** exit 0 を返し、JSON 出力の `.status` が `"FAIL"` である

#### Scenario: FAIL ケース（strict モード）
- **WHEN** missing が非空かつフラグなし（strict = default）で実行する
- **THEN** exit 1 を返す

#### Scenario: quick モード
- **WHEN** missing が非空かつ `--quick` フラグを指定して実行する
- **THEN** exit 0 を返す（WARN のみ）

#### Scenario: JSON 出力構造契約
- **WHEN** `specialist-audit.sh` をデフォルトモードで実行する
- **THEN** 出力が jq でパース可能かつ `.status`、`.missing`、`.actual`、`.expected` キーを含む（SKILL.md の `grep -q '"status":"FAIL"'` がこの出力に対して成立する契約の機械的固定）

### Requirement: grep 契約ロック BATS テスト追加

`plugins/twl/tests/bats/scripts/su-observer-specialist-audit-grep.bats` が存在し、SKILL.md grep 契約を検証しなければならない（SHALL）。

#### Scenario: FAIL 含有 JSONL に grep が反応する
- **WHEN** `.audit/wave-N/specialist-audit.log` にモック JSONL（`"status":"FAIL"` を含む JSON 行）を書き込む
- **THEN** `grep -q '"status":"FAIL"' .audit/wave-N/specialist-audit.log` が exit 0 を返す

#### Scenario: PASS のみ JSONL に grep が反応しない
- **WHEN** `.audit/wave-N/specialist-audit.log` にモック JSONL（`"status":"PASS"` のみの JSON 行）を書き込む
- **THEN** `grep -q '"status":"FAIL"' .audit/wave-N/specialist-audit.log` が exit 1 を返す

### Requirement: SKILL.md 回帰防止（--summary 非使用維持）

`su-observer/SKILL.md` の `for issue_json` ブロックが `--summary` を実行可能コードとして含んでいてはならず（MUST NOT）、grep パターンが `'"status":"FAIL"'` であることを維持する。

#### Scenario: --summary が実行コードとして使われていない
- **WHEN** `sed -n '/for issue_json in/,/WARN: specialist-audit/p' plugins/twl/skills/su-observer/SKILL.md | grep -v '^[[:space:]]*#' | grep -- '--summary'` を実行する
- **THEN** exit 1 を返す（マッチなし）
