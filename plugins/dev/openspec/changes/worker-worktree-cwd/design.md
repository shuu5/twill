## Context

Claude Code は CWD をセッション起動ディレクトリにリセットする挙動がある。現状の Worker は main/ から起動されるため、CWD リセット後に `git branch --show-current` が `main` を返し、IS_AUTOPILOT=false → chain 停止（不変条件C違反）が発生する。

`autopilot-launch.sh` L204-215 に LAUNCH_DIR を決定するロジックがあり、現在は bare repo の場合 `$EFFECTIVE_PROJECT_DIR/main` に固定されている。この部分に `--worktree-dir` 引数を追加し、Pilot から worktree パスを渡すことで解決する。

Pilot 側（`autopilot-orchestrator.sh` の `launch_worker()`）は現在 `worktree-create.sh` を呼び出していない。ADR-008 に従い、Pilot が事前に worktree を作成してからパスを `autopilot-launch.sh --worktree-dir` で渡す形に変更する。これにより Worker の chain から `worktree-create` ステップを除去できる。

## Goals / Non-Goals

**Goals:**

- Worker の cld セッションを worktree ディレクトリで起動する
- CWD リセット後も `git branch --show-current` が正しいブランチ名を返す
- Worker の chain から `worktree-create` ステップを除去する
- Pilot が worktree を事前作成してから Worker を起動する順序を保証する
- 既存 worktree がある場合（リトライ）も冪等に動作する
- 不変条件B を「作成・削除ともに Pilot 専任」に更新する

**Non-Goals:**

- IS_AUTOPILOT 判定の CWD 非依存化（別 Issue #203）
- クリーンアップ処理の集約（別 Issue）
- workflow-setup の manual 実行フローへの影響（manual では worktree-create が引き続き必要）

## Decisions

### 1. autopilot-orchestrator.sh: launch_worker() に worktree-create を追加

`launch_worker()` 内で `autopilot-launch.sh` 呼び出し前に `worktree-create.sh` を実行。

- 引数: `--issue N --project-dir DIR`（クロスリポジトリの場合は `--repo-path DIR` を使用）
- 出力: worktree パス（stdout）を `WORKTREE_DIR` 変数に格納
- 既存 worktree がある場合: `worktree-create.sh` が冪等に処理し既存パスを返す（exit 0）
- `launch_args+=( --worktree-dir "$WORKTREE_DIR" )` で autopilot-launch.sh に渡す

### 2. autopilot-launch.sh: --worktree-dir 引数追加

L204-215 の LAUNCH_DIR 計算ロジックを変更:

```bash
# --worktree-dir 引数が渡された場合はその値を優先
if [[ -n "${WORKTREE_DIR:-}" ]]; then
  LAUNCH_DIR="$WORKTREE_DIR"
elif [[ -d "$EFFECTIVE_PROJECT_DIR/.bare" ]]; then
  LAUNCH_DIR="$EFFECTIVE_PROJECT_DIR/main"
else
  LAUNCH_DIR="$EFFECTIVE_PROJECT_DIR"
fi
```

### 3. chain-steps.sh: worktree-create を Worker chain から除去

`CHAIN_STEPS` 配列から `worktree-create` を削除。Worker は起動時点で既に worktree 内にいるため不要。

`QUICK_SKIP_STEPS` からも削除。

### 4. workflow-setup/SKILL.md: Step 2 を manual 専用に調整

Worker（IS_AUTOPILOT=true）のとき worktree-create を実行しない。IS_AUTOPILOT=false の manual 実行時のみ worktree-create を実行する。

ただし chain-steps.sh から worktree-create が除去されるため、Worker 内での next-step 応答も変わる。workflow-setup SKILL.md のステップ記述を現行の chain 定義に合わせて更新する。

### 5. worktree-create.sh: 冪等性の担保

既存 worktree がある場合の動作確認。現行実装で既存パスを冪等に返せる場合は変更不要。返せない場合は対応を追加。

## Risks / Trade-offs

- **手動実行への影響**: manual（IS_AUTOPILOT=false）で workflow-setup を実行する場合、worktree-create ステップは依然として必要。chain-steps.sh から除去すると manual フローが壊れる。→ chain-steps.sh からは除去し、workflow-setup SKILL.md 側で manual 時のみ worktree-create を実行するロジックを保持する形に調整する。
- **worktree-create.sh の冪等性**: リトライ時に既存 worktree があっても正しく動作する必要がある。既存実装を確認して必要に応じて対応。
- **クロスリポジトリ対応**: `--repo-path` が指定された場合は `EFFECTIVE_PROJECT_DIR` の代わりにそちらを使う必要がある。worktree-create.sh への引数渡しも考慮が必要。
