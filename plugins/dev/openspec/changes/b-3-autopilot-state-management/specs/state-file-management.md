## ADDED Requirements

### Requirement: state-write.sh による状態ファイル書き込み

`state-write.sh` は issue-{N}.json および session.json への書き込みを行うスクリプトである。書き込み時に状態遷移の妥当性を検証しなければならない（SHALL）。

#### Scenario: issue-{N}.json の新規作成
- **WHEN** `state-write.sh --type issue --issue 42 --init --role worker` が実行される
- **THEN** `.autopilot/issues/issue-42.json` が作成され、status が `running` に設定される

#### Scenario: status の正常遷移（running → merge-ready）
- **WHEN** `state-write.sh --type issue --issue 42 --set status=merge-ready --role worker` が実行される
- **THEN** issue-42.json の status が `merge-ready` に更新される

#### Scenario: 不正な状態遷移の拒否
- **WHEN** `state-write.sh --type issue --issue 42 --set status=done --role worker` が実行され、現在の status が `running` である
- **THEN** `running → done` は許可された遷移パスに含まれないため、exit 1 でエラー終了する

#### Scenario: retry_count 超過時の failed → running 拒否
- **WHEN** `state-write.sh --type issue --issue 42 --set status=running --role worker` が実行され、現在の status が `failed` かつ retry_count が 1 以上である
- **THEN** リトライ上限（不変条件E）により exit 1 でエラー終了する

### Requirement: state-read.sh による状態ファイル読み取り

`state-read.sh` は issue-{N}.json および session.json からフィールドを読み取るスクリプトである。存在しないファイルへのアクセスは空文字列を返さなければならない（MUST）。

#### Scenario: 特定フィールドの読み取り
- **WHEN** `state-read.sh --type issue --issue 42 --field status` が実行される
- **THEN** issue-42.json の status フィールドの値が標準出力に出力される

#### Scenario: 全フィールドの読み取り
- **WHEN** `state-read.sh --type issue --issue 42` が実行される（--field 省略）
- **THEN** issue-42.json の全内容が JSON 形式で標準出力に出力される

#### Scenario: 存在しないファイルへのアクセス
- **WHEN** `state-read.sh --type issue --issue 999 --field status` が実行され、issue-999.json が存在しない
- **THEN** 空文字列が標準出力に出力され、exit 0 で正常終了する

### Requirement: Pilot/Worker ロールベースアクセス制御

`state-write.sh` は `--role` フラグにより書き込み対象を制限しなければならない（SHALL）。

#### Scenario: Worker が session.json に書き込みを試みる
- **WHEN** `state-write.sh --type session --set current_phase=2 --role worker` が実行される
- **THEN** Worker は session.json への書き込み権限がないため、exit 1 でエラー終了する

#### Scenario: Pilot が issue-{N}.json に書き込みを試みる
- **WHEN** `state-write.sh --type issue --issue 42 --set status=done --role pilot` が実行される
- **THEN** status=done への遷移は Pilot に許可される（merge-gate PASS 後の done 遷移は Pilot の責務）

#### Scenario: Pilot が issue-{N}.json の status 以外のフィールドに書き込みを試みる
- **WHEN** `state-write.sh --type issue --issue 42 --set current_step=review --role pilot` が実行される
- **THEN** Pilot は issue-{N}.json の status と merged_at 以外のフィールドへの書き込み権限がないため、exit 1 でエラー終了する

### Requirement: 状態遷移テーブルの機械的検証

state-write.sh は以下の遷移テーブルに基づいて status 更新を検証しなければならない（MUST）。

許可される遷移:
- `(初期) → running`（--init 時のみ）
- `running → merge-ready`
- `running → failed`
- `merge-ready → done`
- `merge-ready → failed`
- `failed → running`（retry_count < 1 の場合のみ）

#### Scenario: 全許可遷移の受理
- **WHEN** 上記の許可遷移リストに含まれる遷移が要求される
- **THEN** 遷移が実行され、exit 0 で正常終了する

#### Scenario: done からの遷移拒否
- **WHEN** status が `done` の issue-{N}.json に対して任意の status 更新が要求される
- **THEN** done は終端状態であるため、exit 1 でエラー終了する
