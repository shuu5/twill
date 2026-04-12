## ADDED Requirements

### Requirement: issue-lifecycle-orchestrator --model フラグ

`issue-lifecycle-orchestrator.sh` は `--model <model>` フラグを受け取り、spawn する Worker セッションのモデルを制御しなければならない（SHALL）。デフォルト値は `sonnet` とする。

#### Scenario: --model フラグを指定して起動
- **WHEN** `issue-lifecycle-orchestrator.sh --per-issue-dir <DIR> --model haiku` を実行する
- **THEN** spawn された cld セッションが `--model haiku` で起動される

#### Scenario: --model フラグなしで起動
- **WHEN** `issue-lifecycle-orchestrator.sh --per-issue-dir <DIR>` を `--model` なしで実行する
- **THEN** spawn された cld セッションがデフォルト `sonnet` で起動される

### Requirement: cld-spawn --model オプション

`cld-spawn` は `--model <model>` オプションを受け取り、生成するランチャースクリプトの `cld` 起動コマンドに `--model <model>` を付与しなければならない（SHALL）。

#### Scenario: --model オプションを指定
- **WHEN** `cld-spawn --model sonnet` を呼び出す
- **THEN** 生成されたランチャースクリプトに `cld --model sonnet` が含まれる

#### Scenario: --model オプションなし
- **WHEN** `cld-spawn` を `--model` なしで呼び出す
- **THEN** 生成されたランチャースクリプトに `--model` フラグが含まれず、既存動作と変わらない

## MODIFIED Requirements

### Requirement: co-issue Phase 3 orchestrator 呼び出し

`co-issue SKILL.md` の Phase 3 における `issue-lifecycle-orchestrator.sh` の呼び出しは `--model sonnet` を付与しなければならない（SHALL）。

#### Scenario: Phase 3 での Worker 起動
- **WHEN** `co-issue` が Phase 3 で `issue-lifecycle-orchestrator.sh` を呼び出す
- **THEN** Worker セッションが sonnet モデルで起動され、コスト削減が実現される

### Requirement: co-issue Phase 4 retry 呼び出し

`co-issue SKILL.md` の Phase 4 の retry における `issue-lifecycle-orchestrator.sh` の呼び出しは `--model sonnet` を付与しなければならない（SHALL）。

#### Scenario: Phase 4 retry での Worker 起動
- **WHEN** `co-issue` が Phase 4 で `--resume` 付き retry を実行する
- **THEN** retry Worker セッションも sonnet モデルで起動される
