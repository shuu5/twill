## MODIFIED Requirements

### Requirement: autopilot-plan.sh 引数フォーマット明記

co-autopilot SKILL.md の Step 1（plan生成）において、`autopilot-plan.sh` の引数フォーマットを明記しなければならない（SHALL）。
具体的には、`--issues` の値はスペース区切りであり、カンマ区切りは不可であること、および `--project-dir` または `--repo-mode` が必須であることを示す例を含むこと（SHALL）。

#### Scenario: スペース区切りフォーマット明記
- **WHEN** Pilot が SKILL.md の Step 1 を参照して `autopilot-plan.sh` を呼び出す
- **THEN** `--issues "342 323"` のようにスペース区切り形式で実行し、カンマ区切りによる parse error が発生しない

#### Scenario: --project-dir 必須明記
- **WHEN** Pilot が `autopilot-plan.sh` を呼び出す
- **THEN** `--project-dir "$PROJECT_DIR"` または `--repo-mode` オプションが引数に含まれる

### Requirement: python-env.sh source 指示追加

co-autopilot SKILL.md の Step 3 冒頭において、`python-env.sh` を source する指示が記載されていなければならない（SHALL）。

#### Scenario: PYTHONPATH 設定
- **WHEN** Pilot が SKILL.md の Step 3 を参照して `python3 -m twl.autopilot.session` を呼び出す
- **THEN** 事前に `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/python-env.sh"` が実行されており、`ModuleNotFoundError` が発生しない

#### Scenario: モジュール解決
- **WHEN** `source python-env.sh` が実行される
- **THEN** `PYTHONPATH` に `cli/twl/src` が追加され、`twl.autopilot` モジュールが正しく解決される

### Requirement: orchestrator --session-file 絶対パス例明示

co-autopilot SKILL.md において、`orchestrator` の `--session-file` 引数に絶対パスを渡す例が示されていなければならない（SHALL）。

#### Scenario: 絶対パスによる orchestrator 起動
- **WHEN** Pilot が SKILL.md を参照して `orchestrator` を呼び出す
- **THEN** `--session-file "${AUTOPILOT_DIR}/session.json"` のように絶対パス形式で指定され、パスエラーが発生しない
