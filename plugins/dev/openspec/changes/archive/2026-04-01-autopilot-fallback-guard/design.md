## Context

現在の autopilot 配下判定は `state-read.sh` に依存する3層構造:

1. **第1層**: `auto-merge.md` Step 0 の `IS_AUTOPILOT` 判定（state-read.sh 経由）
2. **第2層**: `all-pass-check.md` Step 1.5 の `IS_AUTOPILOT` 判定（state-read.sh 経由）
3. **第3層**: `merge-gate-execute.sh` の CWD ガード（worktrees/ 配下拒否のみ）

第1層・第2層は同じ `state-read.sh` を使用しており、`AUTOPILOT_DIR` が空や不正な場合に同時破壊される。第3層は CWD ベースのため、main/ から実行される場合は機能しない。

`state-read.sh` は `AUTOPILOT_DIR` 環境変数に依存し、デフォルトは `$PROJECT_ROOT/.autopilot`。Worker が AUTOPILOT_DIR を正しく継承できない場合（Bug A）、`issue-{N}.json` を発見できず `IS_AUTOPILOT=false` と判定する。

## Goals / Non-Goals

**Goals:**

- `state-read.sh` とは独立した第4層フォールバックガードを追加し、`IS_AUTOPILOT=false` 誤判定時も Worker の merge を防止する
- 非 autopilot 通常利用（`issue-{N}.json` 不在 + `ISSUE_NUM` 未設定）で既存動作に影響しないこと
- 既存の `state-read.sh` のデフォルト動作（D1: 失敗時は非 autopilot）を変更しないこと

**Non-Goals:**

- Bug A（AUTOPILOT_DIR 伝搬バグ）の根本修正
- `state-read.sh` のデフォルト動作変更
- 第3層 CWD ガードの拡張

## Decisions

### D1: `issue-{N}.json` 直接ファイル存在確認（auto-merge.md）

`auto-merge.md` Step 0 の `IS_AUTOPILOT` 判定後、`IS_AUTOPILOT=false` かつ `ISSUE_NUM` が設定されている場合にフォールバックチェックを実行:

```bash
# フォールバック: state-read.sh とは独立した直接ファイル存在確認
if [[ "$IS_AUTOPILOT" == "false" && -n "${ISSUE_NUM:-}" ]]; then
  MAIN_WORKTREE_PATH="$(git worktree list --porcelain | awk '/^worktree / { wt=substr($0,10) } /branch refs\/heads\/main$/ { print wt; exit }')"
  if [[ -n "$MAIN_WORKTREE_PATH" ]]; then
    MAIN_AUTOPILOT_DIR="${MAIN_WORKTREE_PATH}/.autopilot"
    if [[ -f "${MAIN_AUTOPILOT_DIR}/issue-${ISSUE_NUM}.json" ]]; then
      echo "⚠️ フォールバックガード発動: issue-${ISSUE_NUM}.json が存在するため merge を禁止"
      bash scripts/state-write.sh --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready
      exit 0
    fi
  fi
fi
```

**根拠**: main worktree の `.autopilot/` を直接参照することで、AUTOPILOT_DIR 伝搬バグの影響を回避する。`git worktree list --porcelain` は空白を含むパスでも安全にパースできる。

### D2: Worker ロール検出（merge-gate-execute.sh）

tmux window 名パターン `ap-#N`（N は数字）を正規表現で検出:

```bash
CURRENT_WINDOW=$(tmux display-message -p '#W' 2>/dev/null || echo "")
if [[ "$CURRENT_WINDOW" =~ ^ap-#[0-9]+$ ]]; then
  echo "[merge-gate-execute] ERROR: autopilot Worker（${CURRENT_WINDOW}）からの merge 実行は禁止されています" >&2
  exit 1
fi
```

**根拠**: autopilot の Worker は常に `ap-#N` 形式の tmux window で起動される。この命名規則は co-autopilot で確立されており、独立したシグナルとして利用できる。

### D3: `all-pass-check.md` への適用対象外

`all-pass-check.md` は merge を実行しない（status 遷移のみ）ため、フォールバックガードの追加対象外。`merge-ready` への遷移自体は安全（Pilot が merge-gate で判定するため）。

## Risks / Trade-offs

- **tmux 非使用環境**: D2 の Worker ロール検出は tmux 依存。tmux 外から実行された場合はフォールバックしない（CWD ガードと D1 で補完）
- **main worktree 検出の信頼性**: `git worktree list` が main worktree を正しく返すことに依存。bare repo 構成では安定している
- **パフォーマンス**: `git worktree list` の追加呼び出しが発生するが、merge 操作自体が重いため無視できる
