## Why

`skills/co-issue/SKILL.md` の Step 3b に記載されたエスケープ処理は疑似コードとして LLM の解釈に依存しており、プロジェクト設計哲学「LLM に注意してではなく機械的制御で再発防止」に違反する。Issue body に `</review_target>` 等のタグが含まれる場合、エスケープ漏れによりプロンプトインジェクションが発生するリスクがある。

## What Changes

- `scripts/` 配下にエスケープ処理 Bash スクリプトを新規作成（`&`→`&amp;`、`<`→`&lt;`、`>`→`&gt;` の順で置換）
- `skills/co-issue/SKILL.md` の Step 3b を更新（疑似コード → スクリプト呼び出し指示に置換）
- `tests/bats/scripts/` 配下にエスケープ処理の bats テスト追加
- `deps.yaml` に新規スクリプトエントリを追加（type: script）
- `skills/co-issue/SKILL.md` の Step 3b にアーキテクチャ制約を明記（全 specialist は必ずエスケープ済み入力を受け取る）

## Capabilities

### New Capabilities

- **エスケープスクリプト**: `scripts/escape-issue-body.sh`（または同等のスクリプト名）が Issue body の HTML エスケープを機械的に実行する
- **bats テスト**: `</review_target>`、`&`、空文字列、複数行入力のエスケープ検証テスト

### Modified Capabilities

- **co-issue Step 3b**: specialist 呼び出し前のエスケープ処理が LLM 疑似コードからスクリプト呼び出しに変わり、機械的に強制される
- **specialist スコープ境界**: issue-critic、issue-feasibility、worker-codex-reviewer の全てに対してエスケープ済み入力が保証される

## Impact

- `skills/co-issue/SKILL.md`（Step 3b を修正）
- `scripts/escape-issue-body.sh`（新規作成）
- `tests/bats/scripts/test_escape_issue_body.bats`（新規作成）
- `deps.yaml`（script エントリ追加）
- 既存 co-issue bats テストへの影響なし（エスケープ処理は呼び出し側の変更のみ）
