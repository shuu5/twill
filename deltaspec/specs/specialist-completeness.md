## Requirements

### Requirement: specialist-audit.sh スクリプト

`plugins/twl/scripts/specialist-audit.sh` を新規作成し、Worker JSONL から specialist completeness を独立検証しなければならない（SHALL）。

- 入力: `--issue <N>` または `--jsonl <path>`（排他）
- 期待集合: `pr-review-manifest.sh --mode <phase>` を呼び出して動的生成しなければならない（SHALL）
- 実行集合: JSONL から `"subagent_type":"twl:twl:worker-*"` を抽出しなければならない（SHALL）
- 突合: `expected ⊆ actual` を検証し、missing 非空を FAIL としなければならない（SHALL）
- exit code: `0=PASS/WARN`、`1=FAIL` の 2 値のみとしなければならない（SHALL）
- 環境変数 `SPECIALIST_AUDIT_MODE=warn` で全 FAIL を WARN に降格しなければならない（SHALL）
- `SKIP_SPECIALIST_AUDIT=1` で完全スキップしなければならない（SHALL）

#### Scenario: JSONL に全期待 specialist が存在する場合
- **WHEN** `specialist-audit.sh --issue 740 --mode merge-gate` を実行し、JSONL に全期待 specialist が存在する
- **THEN** stdout に `{"status":"PASS",...}` を出力し exit 0

#### Scenario: JSONL に missing specialist がある場合（strict モード）
- **WHEN** `SPECIALIST_AUDIT_MODE=strict specialist-audit.sh --issue 740` を実行し、missing specialist がある
- **THEN** stdout に `{"status":"FAIL","missing":[...]}` を出力し exit 1

#### Scenario: warn モードで missing がある場合
- **WHEN** `SPECIALIST_AUDIT_MODE=warn specialist-audit.sh --issue 740` を実行し、missing がある
- **THEN** stdout に `{"status":"WARN",...}` を出力し exit 0

#### Scenario: --warn-only フラグ使用
- **WHEN** `specialist-audit.sh --issue 740 --warn-only` を実行し、missing がある
- **THEN** exit 0 で終了する

#### Scenario: JSONL 解決失敗
- **WHEN** 対応プロジェクトディレクトリが存在しない Issue 番号を指定する
- **THEN** `{"status":"WARN","reason":"jsonl_resolution_failed"}` を出力し exit 0

### Requirement: merge-gate-check-spawn.sh JSONL 独立検証

`merge-gate-check-spawn.sh` の末尾（MANIFEST_FILE ブロック外）に specialist-audit.sh 呼び出しを追加し、JSONL 独立検証を実行しなければならない（SHALL）。

- `${CLAUDE_PLUGIN_ROOT:-plugins/twl}/scripts/specialist-audit.sh` で解決しなければならない（SHALL）
- `set -euo pipefail` 下で `|| audit_exit=$?` で exit code を捕捉しなければならない（SHALL）
- `--quick` フラグを呼び出し側が判定して渡さなければならない（SHALL）
- FAIL 時は stderr に `REJECT: specialist-audit FAIL` を出力しなければならない（SHALL）
- JSONL 解決失敗時は exit 0 で継続しなければならない（SHALL）

#### Scenario: 正常な merge-gate 実行
- **WHEN** `merge-gate-check-spawn.sh` が実行され、specialist-audit.sh が PASS を返す
- **THEN** exit 0 で完了し、既存の MANIFEST_FILE 検証も維持される

#### Scenario: specialist-audit FAIL（strict モード）
- **WHEN** `SPECIALIST_AUDIT_MODE=strict` で specialist-audit.sh が FAIL を返す
- **THEN** `REJECT: specialist-audit FAIL` を stderr に出力し exit 1

### Requirement: su-observer Wave 完了時の自動監査

`su-observer/SKILL.md` の Wave 完了セクション（L369 の `twl audit snapshot` 直後）に specialist-audit.sh 呼び出しを追加し、全 Issue の specialist completeness を一括監査しなければならない（SHALL）。

- `--warn-only` フラグで merge を阻害しない形で監査しなければならない（SHALL）
- 結果を `.audit/wave-${WAVE_NUM}/specialist-audit.log` に追記しなければならない（SHALL）

#### Scenario: Wave 完了時の一括監査
- **WHEN** Wave 完了を検知し、su-observer が Wave 完了処理を実行する
- **THEN** 全 issue-*.json に対して specialist-audit.sh が --warn-only で実行される
