## ADDED Requirements

### Requirement: issue-lifecycle-orchestrator.sh 新規作成

`plugins/twl/scripts/issue-lifecycle-orchestrator.sh` が `spec-review-orchestrator.sh` のコード構造を流用して新規作成されなければならない（SHALL）。

#### Scenario: スクリプト存在確認
- **WHEN** `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` を確認する
- **THEN** ファイルが存在し実行可能である

### Requirement: orchestrator 入力インターフェース

`--per-issue-dir <abs-path>` で `.controller-issue/<sid>/per-issue/` 絶対パスを受け取り、絶対パス検証とパストラバーサル対策を施さなければならない（SHALL）。

#### Scenario: 絶対パス検証
- **WHEN** `--per-issue-dir ./relative/path` を渡す
- **THEN** "絶対パスで指定してください" エラーで exit 1

#### Scenario: パストラバーサル対策
- **WHEN** `--per-issue-dir /abs/../path` を渡す
- **THEN** パストラバーサルエラーで exit 1

### Requirement: tmux window 決定論的命名

tmux window 名は `coi-<sid8>-<index>` 形式で一意に決定されなければならない（MUST）。flock で衝突を回避しなければならない（SHALL）。

#### Scenario: 決定論的 window 名
- **WHEN** 同一 sid の 2 つの subdir を spawn する
- **THEN** それぞれ `coi-<sid8>-0`, `coi-<sid8>-1` の window 名が割り当てられる

### Requirement: printf '%q' クォート

tmux new-window のコマンド引数が全て `printf '%q'` でクォートされなければならない（MUST）。

#### Scenario: shell injection 対策
- **WHEN** orchestrator.sh の tmux 呼び出し部分を grep する
- **THEN** `printf '%q'` が使われている

### Requirement: `|| continue` による失敗局所化

1 window の spawn 失敗が全体に波及してはならない（MUST NOT）。各 subdir の spawn は `|| continue` で失敗を局所化しなければならない（SHALL）。

#### Scenario: spawn 失敗の局所化
- **WHEN** 3 subdir のうち 1 つの tmux spawn が失敗する
- **THEN** 残り 2 つの subdir は正常に処理が続く

### Requirement: Resume 対応

既存 window または `STATE=done` の subdir はスキップされなければならない（SHALL）。`STATE=failed` の subdir はリセットして再実行されなければならない（SHALL）。

#### Scenario: done 済みスキップ
- **WHEN** subdir の OUT/report.json が既に存在する
- **THEN** その subdir の window spawn をスキップする

#### Scenario: failed リセット
- **WHEN** subdir の STATE が "failed" である
- **THEN** STATE をリセットして再実行する

### Requirement: 完了検知ポーリング

全 subdir の `OUT/report.json` が出揃うまでポーリングし、タイムアウト（MAX_POLL * POLL_INTERVAL 秒）で exit 1 しなければならない（SHALL）。

#### Scenario: 正常完了
- **WHEN** 全 subdir に OUT/report.json が出揃う
- **THEN** exit 0 で正常終了する

#### Scenario: タイムアウト
- **WHEN** MAX_POLL 回ポーリングしても全 subdir が完了しない
- **THEN** exit 1 でタイムアウト終了する

### Requirement: cld 位置引数起動

orchestrator が `cld '<prompt>'` 形式（位置引数）で起動し、`-p`/`--print` を使ってはならない（MUST NOT）。

#### Scenario: cld 起動方式確認
- **WHEN** issue-lifecycle-orchestrator.sh の cld 呼び出し部分を確認する
- **THEN** `-p` または `--print` フラグが使われていない
