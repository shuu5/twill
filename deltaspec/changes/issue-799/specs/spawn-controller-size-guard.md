## ADDED Requirements

### Requirement: spawn-controller.sh prompt size guard

`spawn-controller.sh` は PROMPT_BODY 代入直後・FINAL_PROMPT 生成前にプロンプトの行数を検査し、30 行を超える場合は stderr に警告を出力しなければならない（SHALL）。

#### Scenario: 30 行以下の prompt は警告なし
- **WHEN** `PROMPT_FILE` の行数が 30 行以下で `spawn-controller.sh` を呼び出す
- **THEN** stderr に `WARN: prompt size` が出力されない

#### Scenario: 31 行以上の prompt は警告を出力
- **WHEN** `PROMPT_FILE` の行数が 31 行以上で `spawn-controller.sh` を呼び出す
- **THEN** stderr に `WARN: prompt size <N> lines exceeds recommended 30 lines.` が出力される

#### Scenario: --force-large フラグで警告を suppress
- **WHEN** `PROMPT_FILE` の行数が 31 行以上かつ `--force-large` フラグを渡して `spawn-controller.sh` を呼び出す
- **THEN** stderr に `WARN: prompt size` が出力されない

#### Scenario: --force-large は cld-spawn 引数から strip される
- **WHEN** `--force-large` フラグを渡して `spawn-controller.sh` を呼び出す
- **THEN** `cld-spawn` に渡される引数に `--force-large` が含まれない（mock で検証）

#### Scenario: 空の prompt は警告なし
- **WHEN** `PROMPT_FILE` が空（0 行）で `spawn-controller.sh` を呼び出す
- **THEN** stderr に `WARN: prompt size` が出力されない（`printf '%s\n' ''` の挙動を明示確認）

### Requirement: --force-large フラグの安全実装

`--force-large` のパース・除去は `set -u` 安全な方式で実装しなければならない（MUST）。空配列に対して `${arr[@]}` を展開する際は `${arr[@]+${arr[@]}}` 形式を使用する。

#### Scenario: set -u 環境での空配列安全性
- **WHEN** `NEW_ARGS` が空配列（`--force-large` のみの引数）の状態で `set --` を実行する
- **THEN** `unbound variable` エラーが発生しない
