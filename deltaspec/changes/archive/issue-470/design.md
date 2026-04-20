## Context

bare repo 構成（`twill/.bare`, `twill/main/`, `twill/.autopilot/`）において、state CLI の `_autopilot_dir()` fallback は `git worktree list` で main worktree path を取得し `<main_wt>/.autopilot` を返す。しかし実際の state file は bare sibling（`<main_wt>/../.autopilot`）に配置されており、Pilot が `AUTOPILOT_DIR` 未設定で実行すると存在しないパスを参照してしまう。

また `_PILOT_ISSUE_ALLOWED_KEYS` に `pr` が含まれないため、Worker が `pr` を書き残さなかったケースで Pilot による recovery（Emergency Bypass など）が不能になる。

## Goals / Non-Goals

**Goals:**
- `_autopilot_dir()` fallback で bare sibling（`<main_wt>/../.autopilot`）を優先的に試す
- `_PILOT_ISSUE_ALLOWED_KEYS` に `pr` を追加する
- ファイル不在時エラーメッセージに試したパスと `AUTOPILOT_DIR` export 推奨を追加する
- `autopilot-orchestrator.sh` で `AUTOPILOT_DIR` 未設定時 warning を出す
- `co-autopilot/SKILL.md` に `AUTOPILOT_DIR` export 必須を明示する
- pytest で bare sibling / main worktree 両パターンのテストを追加する

**Non-Goals:**
- `AUTOPILOT_DIR` の自動 export（env propagation の根本的な変更）
- state.py 内部からの gh API 呼び出し（PR 実在検証は呼び出し元の責務）
- bare repo でない環境（standard git repo）の動作変更

## Decisions

### `_autopilot_dir()` の fallback 順序

現在: env var → main worktree 配下 → first real worktree 配下 → cwd

変更後: env var → bare sibling（`<main_wt>/../.autopilot`が存在する場合） → main worktree 配下（`<main_wt>/.autopilot`が存在する場合）→ first real worktree 配下 → cwd

bare sibling を main worktree 配下より先に試す根拠: `twill/.autopilot/` が実際の配置場所であることを本機で確認済み。存在確認（`Path.exists()`）で判定するため、bare sibling が存在しない環境では既存動作にフォールバックする。

### `pr` フィールド許可の設計

state.py 内部では RBAC チェックのみ担う。`pr` の値が実在する GitHub PR 番号かどうかの検証は呼び出し元（orchestrator.sh や Pilot コマンド）の責務とする。これにより state.py が外部 API 依存を持たない純粋な状態管理モジュールになる。

### エラーメッセージ設計

`StateError` の文字列に以下を追加する:
- 実際に試したパス一覧（`tried: [...]`）
- `AUTOPILOT_DIR` env var の export 方法（`export AUTOPILOT_DIR=<path>`）

`_resolve_file()` がエラーを raise する箇所（FileNotFoundError / StateError）でこの情報を付与する。

## Risks / Trade-offs

- bare sibling の存在確認を `Path.exists()` で行うため、存在しない環境では extra filesystem stat が 1 回増加するが無視できるコスト
- `_PILOT_ISSUE_ALLOWED_KEYS` への `pr` 追加は Pilot の書き込み権限拡張。誤用リスクは呼び出し元の検証で緩和する
