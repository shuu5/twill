## MODIFIED Requirements

### Requirement: issue_to_entry キーのentry形式統一

`poll_phase()` 内の `issue_to_entry` 連想配列は、キーを `repo_id:issue_num`（entry 形式）で保持しなければならない（SHALL）。

#### Scenario: 単一リポで poll_phase を実行する
- **WHEN** entries が `["_default:42"]` の形式で渡された場合
- **THEN** `issue_list` に `"_default:42"` が格納され、`issue_to_entry["_default:42"]` が `"_default:42"` を返す

#### Scenario: クロスリポで同一番号の Issue が同一 Phase に存在する
- **WHEN** entries が `["loom:42", "loom-plugin-dev:42"]` の形式で渡された場合
- **THEN** `issue_list` に両エントリが格納され、どちらも上書きなく保持される

### Requirement: cleaned_up キーのentry形式統一

`cleaned_up` 連想配列は entry 形式（`repo_id:issue_num`）をキーとして使用しなければならない（SHALL）。

#### Scenario: Issue が done/failed になった後の二重クリーンアップ防止
- **WHEN** entry `"_default:42"` の status が `done` になった場合
- **THEN** `cleaned_up["_default:42"]` が設定され、同 entry に対する `cleanup_worker` の二重呼び出しが防止される

### Requirement: state-read/state-write への --repo 引数付与

クロスリポ環境では `state-read.sh` / `state-write.sh` の呼び出し時に `--repo "$repo_id"` を渡さなければならない（SHALL）。`_default` の場合は省略する。

#### Scenario: クロスリポ Issue の状態読み込み
- **WHEN** entry の `repo_id` が `"loom"` で `issue_num` が `42` の場合
- **THEN** `state-read.sh --type issue --repo loom --issue 42 --field status` が呼ばれる

#### Scenario: 単一リポ Issue の状態読み込み
- **WHEN** entry の `repo_id` が `"_default"` で `issue_num` が `42` の場合
- **THEN** `state-read.sh --type issue --issue 42 --field status` が呼ばれる（`--repo` 引数なし）

### Requirement: window_name のクロスリポ対応

tmux ウィンドウ名は `_default` の場合は `ap-#N` 形式を維持し、クロスリポの場合は `ap-{repo_id}-#N` 形式としなければならない（SHALL）。

#### Scenario: 単一リポでのウィンドウ名生成
- **WHEN** entry の `repo_id` が `"_default"` の場合
- **THEN** `window_name` が `"ap-#42"` 形式で生成される

#### Scenario: クロスリポでのウィンドウ名生成
- **WHEN** entry の `repo_id` が `"loom-plugin-dev"` の場合
- **THEN** `window_name` が `"ap-loom-plugin-dev-#42"` 形式で生成される
