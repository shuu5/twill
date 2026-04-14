## Context

twill の autopilot パイプラインは現在、中間成果物を揮発性ストレージ（/tmp の specialist manifest）または上書き型ストレージ（checkpoint.json）に保存している。bare repo 構造（`.bare/` + `main/` worktree + `worktrees/<branch>/`）では `git rev-parse --show-toplevel` がworktreeのルートを返すため、プロジェクトルートの特定には同コマンドを使用する。

audit 機能は「opt-in」設計（環境変数 `TWL_AUDIT=1` または `.audit/.active` ファイルの存在）で有効化し、無効時は既存動作に一切影響しない。

## Goals / Non-Goals

**Goals:**

- `twl audit on/off/status` サブコマンドで audit セッションを管理する
- `TWL_AUDIT=1` OR `.audit/.active` 存在時に中間成果物を永続化する
- specialist manifest、checkpoint、state 遷移履歴を `.audit/<run-id>/` に保全する
- `audit.py` を循環依存なしの独立モジュールとして設計する
- Worker セッションへ `TWL_AUDIT_DIR`（絶対パス）を launcher 経由で伝搬する

**Non-Goals:**

- `twl audit report` レポート生成（後続 Issue）
- observer による `.audit/<run-id>/` 分析・Issue 起票（後続 Issue）
- `TWL_CHAIN_TRACE` の変更
- `audit_history.py`（既存 Layer 1 empirical audit）の変更

## Decisions

### D1: audit.py の循環依存回避

`audit.py` は `checkpoint.py` / `state.py` に依存しない（stdlib のみ使用）。`checkpoint.py` と `state.py` が `audit.py` を import する一方向依存とする。これにより既存モジュールの import チェーンを汚染しない。

### D2: 有効化判定は OR ロジック

`TWL_AUDIT=1` 環境変数または `.audit/.active` ファイル存在のいずれかで audit を有効化する。環境変数は一時的な有効化（CI・テスト）、`.active` ファイルは永続的な有効化（通常利用）に対応する。

### D3: `_project_root()` は git rev-parse 依存

`git rev-parse --show-toplevel` でプロジェクトルートを特定する。bare repo の worktree でも正しいパスが返る。git 管理外のディレクトリでの実行はサポート外とする。

### D4: audit_dir 解決は TWL_AUDIT_DIR 優先

`TWL_AUDIT_DIR` env var → `.audit/.active` の順で解決する。Worker セッションでは launcher が `resolve_audit_dir()` を呼び出した結果（絶対パス）を `TWL_AUDIT_DIR` に設定して env_flags 経由で渡す。環境変数の単純引き継ぎではなく、launcher が解決責任を持つ。

### D5: checkpoint 保全は上書き前コピー

`checkpoint.write()` 内で `is_audit_active()` が true の場合、既存ファイルを `<step>-<ISO8601>.json` としてコピーしてから上書きする。タイムスタンプは `datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")` で生成する。

### D6: state-log.jsonl はフィールド単位の追記

state write 系メソッドで変更が生じた場合、変更フィールド・変更前後の値・ロール（worker/pilot）・タイムスタンプを JSONL で追記する。state file 全体の diff ではなく、フィールド単位の変更レコードとする。

### D7: check-specialist-completeness.sh のコピーは削除より前

既存の `rm -f /tmp/.specialist-*` より前に audit コピーを実行する。既存の削除処理を後回しにすることで、コピーの失敗が削除をブロックしないよう `|| true` でエラーを無視する。

## Risks / Trade-offs

- **ディスク使用量**: audit 有効時に checkpoint が step ごとに蓄積される。長時間の autopilot run では数 MB 程度になる可能性がある。`.audit/` は `.gitignore` で追跡除外するため、リポジトリへの影響はない。
- **パフォーマンス**: `is_audit_active()` は毎回 `os.path.isfile()` を呼び出す。頻繁な state write がある場合にわずかな I/O オーバーヘッドが生じる。許容範囲内と判断する。
- **race condition**: 複数の Worker が同一 audit dir に並行書き込みする場合、state-log.jsonl の行が混在する可能性がある。JSONL 追記は行単位でアトミックなため、読み取り時に問題は生じない。
- **audit off 未実行のまま終了**: `.audit/.active` が残存し続ける。`twl audit status` で確認可能。将来的に autopilot 終了時の自動 off を検討するが、本 Issue では対応しない。
