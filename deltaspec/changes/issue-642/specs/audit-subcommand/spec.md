## ADDED Requirements

### Requirement: twl audit on サブコマンド

`twl audit on [--run-id ID]` を実行すると、`.audit/<run-id>/` ディレクトリが作成され、`.audit/.active` ファイルが書き出されなければならない（SHALL）。`--run-id` を省略した場合は `<unix-timestamp>_<4文字ランダム>` 形式の run-id が自動生成される。

#### Scenario: run-id 自動生成で audit on
- **WHEN** `twl audit on` を引数なしで実行する
- **THEN** `.audit/<timestamp>_<random>/` ディレクトリが作成され、`.audit/.active` に `{"run_id":...,"started_at":...,"audit_dir":...}` が JSON で書き出される

#### Scenario: 指定 run-id で audit on
- **WHEN** `twl audit on --run-id my-run-001` を実行する
- **THEN** `.audit/my-run-001/` ディレクトリが作成され、`.audit/.active` の `run_id` が `"my-run-001"` になる

### Requirement: twl audit off サブコマンド

`twl audit off` を実行すると、`.audit/.active` が削除され、`.audit/<run-id>/index.json` が生成されなければならない（SHALL）。audit が有効でない場合はエラーメッセージを表示して終了する。

#### Scenario: 正常な audit off
- **WHEN** `.audit/.active` が存在する状態で `twl audit off` を実行する
- **THEN** `.audit/.active` が削除され、`.audit/<run-id>/index.json` に `{run_id, started_at, ended_at, files}` が書き出される

#### Scenario: audit 未開始での off
- **WHEN** `.audit/.active` が存在しない状態で `twl audit off` を実行する
- **THEN** `audit is not active` エラーメッセージを表示して終了する

### Requirement: twl audit status サブコマンド

`twl audit status` を実行すると、現在の audit 状態（active/inactive、run-id）が表示されなければならない（SHALL）。

#### Scenario: audit active 時の status
- **WHEN** `.audit/.active` が存在する状態で `twl audit status` を実行する
- **THEN** `active: true, run_id: <id>, audit_dir: <path>` を含む情報が表示される

#### Scenario: audit inactive 時の status
- **WHEN** `.audit/.active` が存在しない状態で `twl audit status` を実行する
- **THEN** `active: false` が表示される

### Requirement: is_audit_active() ヘルパー

`is_audit_active()` は `TWL_AUDIT=1` 環境変数または `.audit/.active` ファイルの存在のいずれかで `True` を返さなければならない（SHALL）。両方とも存在しない場合は `False` を返す。

#### Scenario: 環境変数での有効化
- **WHEN** `TWL_AUDIT=1` 環境変数が設定されている
- **THEN** `is_audit_active()` が `True` を返す

#### Scenario: ファイルでの有効化
- **WHEN** `.audit/.active` ファイルが存在する
- **THEN** `is_audit_active()` が `True` を返す（環境変数なしでも）

#### Scenario: 無効状態
- **WHEN** `TWL_AUDIT` が未設定かつ `.audit/.active` が存在しない
- **THEN** `is_audit_active()` が `False` を返す

### Requirement: resolve_audit_dir() ヘルパー

`resolve_audit_dir()` は `TWL_AUDIT_DIR` 環境変数 → `.audit/.active` の順で audit ディレクトリを解決し、`Path` を返さなければならない（SHALL）。いずれも存在しない場合は `None` を返す。

#### Scenario: 環境変数からの解決
- **WHEN** `TWL_AUDIT_DIR=/abs/path/to/audit` が設定されている
- **THEN** `resolve_audit_dir()` が `Path("/abs/path/to/audit")` を返す

#### Scenario: .active ファイルからの解決
- **WHEN** `TWL_AUDIT_DIR` が未設定で `.audit/.active` が存在する
- **THEN** `resolve_audit_dir()` が `.audit/.active` の `audit_dir` フィールドをプロジェクトルート相対で解決した絶対パスを返す

### Requirement: specialist ファイルの自動保全

`TWL_AUDIT=1` かつ `TWL_AUDIT_DIR` が設定されている場合、`check-specialist-completeness.sh` は `/tmp/.specialist-*` ファイルを `.audit/<run-id>/specialists/` にコピーしなければならない（SHALL）。このコピーは既存の削除処理より前に実行される。

#### Scenario: audit 有効時の specialist 保全
- **WHEN** `TWL_AUDIT=1` かつ `TWL_AUDIT_DIR` が設定された状態で `check-specialist-completeness.sh` が実行される
- **THEN** `/tmp/.specialist-manifest-*.txt` および `/tmp/.specialist-spawned-*.txt` が `.audit/<run-id>/specialists/` にコピーされた後に削除される

#### Scenario: audit 無効時の動作不変
- **WHEN** `TWL_AUDIT` が未設定の状態で `check-specialist-completeness.sh` が実行される
- **THEN** 既存の動作と同一（コピーなしで削除のみ実行）

### Requirement: checkpoint 自動保全

`is_audit_active()` が true の場合、`checkpoint.write()` は既存の checkpoint ファイルをタイムスタンプ付きで `.audit/<run-id>/checkpoints/` にコピーしてから上書きしなければならない（SHALL）。

#### Scenario: checkpoint 保全コピー
- **WHEN** audit が有効な状態で `checkpoint.write("phase-review", data)` を実行する
- **THEN** 既存の `phase-review.json` が `.audit/<run-id>/checkpoints/phase-review-<ISO8601>.json` にコピーされてから新データで上書きされる

#### Scenario: checkpoint 初回 write は保全不要
- **WHEN** audit が有効な状態で既存ファイルなしに `checkpoint.write()` を実行する
- **THEN** コピーなしで通常通り新規書き込みされる

### Requirement: state 遷移ログ

`is_audit_active()` が true の場合、state.py の write 系メソッドは変更フィールド・変更前後の値・ロール・タイムスタンプを `.audit/<run-id>/state-log.jsonl` に追記しなければならない（SHALL）。

#### Scenario: state 変更のログ記録
- **WHEN** audit が有効な状態で `state.py` の write メソッドがフィールドを変更する
- **THEN** `{"ts":...,"issue":N,"field":"<field>","old":"<before>","new":"<after>","role":"worker"|"pilot"}` が `state-log.jsonl` に追記される

#### Scenario: 変更なし時はログ不記録
- **WHEN** audit が有効な状態で write メソッドが既存値と同一の値を設定する
- **THEN** `state-log.jsonl` への追記は行われない

### Requirement: launcher による TWL_AUDIT_DIR 伝搬

`TWL_AUDIT=1` の場合、`launcher.py` は `resolve_audit_dir()` を呼び出して解決した絶対パスを `TWL_AUDIT_DIR` として Worker の `env_flags` に設定しなければならない（SHALL）。環境変数の単純引き継ぎではなく、launcher が解決責任を持つ。

#### Scenario: Worker への audit 環境変数伝搬
- **WHEN** `TWL_AUDIT=1` が設定された状態で `launcher.py` が Worker を起動する
- **THEN** Worker の env_flags に `TWL_AUDIT=1` と `TWL_AUDIT_DIR=<絶対パス>` が設定される

### Requirement: .gitignore への .audit/ 追加

`.gitignore` に `.audit/` エントリが追加されなければならない（SHALL）。audit ディレクトリはリポジトリに追跡されない。

#### Scenario: .audit/ の gitignore 確認
- **WHEN** `.audit/` ディレクトリが作成される
- **THEN** `git status` に `.audit/` が untracked として表示されない（gitignore によって除外される）

### Requirement: deps.yaml への audit.py エントリ追加

`deps.yaml` に `audit.py` 新規モジュールのエントリが追加されなければならない（SHALL）。deps.yaml は SSOT として依存関係を管理する。

#### Scenario: deps.yaml の audit.py エントリ
- **WHEN** `loom --check` を実行する
- **THEN** `audit.py` が deps.yaml に登録されており、チェックが通る
