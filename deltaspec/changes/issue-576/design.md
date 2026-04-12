## Context

`autopilot-orchestrator.sh` は `launch_worker()` 関数内で CRG graph DB symlink を作成する（#532）。現行実装（line 324-329）は main worktree 自己参照を防ぐために `realpath` を使っているが、bare repo + worktree 構造では `realpath` の解決結果がアクセス経路（symlink 経由 / 直接）によって変わるため不安定。

現行コード（line 324-329）:
```bash
local _crg_main="${effective_project_dir}/main/.code-review-graph"
local _is_main=0
[[ "$(realpath "$worktree_dir" 2>/dev/null)" == "$(realpath "${effective_project_dir}/main" 2>/dev/null)" ]] && _is_main=1
[[ -d "$_crg_main" && "$_is_main" -eq 0 && ! -e "$worktree_dir/.code-review-graph" ]] && ln -sf "$_crg_main" "$worktree_dir/.code-review-graph"
```

`effective_project_dir` は line 274 で `PROJECT_DIR`（または `ISSUE_REPO_PATH`）から取得される。`TWILL_REPO_ROOT` は常に twill モノリポルート（`PROJECT_DIR`）を指し、`ISSUE_REPO_PATH` とは独立。

## Goals / Non-Goals

**Goals:**
- `TWILL_REPO_ROOT` を `effective_project_dir`（= `PROJECT_DIR`）から export する
- CRG symlink 参照先を `${TWILL_REPO_ROOT}/main/.code-review-graph` に変更
- `_is_main` 判定を文字列比較（末尾スラッシュ strip）に変更
- `realpath` ベースのガード（line 328）を削除

**Non-Goals:**
- `issue-lifecycle-orchestrator.sh` の CRG 対応
- `cld-spawn` への `TWILL_REPO_ROOT` 伝搬
- クロスリポジトリ時の CRG 参照先切り替え（`ISSUE_REPO_PATH` 設定時）

## Decisions

### D1: `TWILL_REPO_ROOT` の export タイミング

`launch_worker()` の `effective_project_dir` 確定直後（line 274-276 の後、worktree 作成前）に export する。  
**理由**: `effective_project_dir` が確定したタイミングが最も自然。後続の全処理で参照可能。

```bash
# line 276 の後に追加
export TWILL_REPO_ROOT="${PROJECT_DIR}"
```

`ISSUE_REPO_PATH` が設定されている場合も `TWILL_REPO_ROOT` は twill モノリポルート固定（`PROJECT_DIR`）とする。CRG DB は常に twill モノリポの `main/.code-review-graph` を参照する。

### D2: CRG symlink 参照先

```bash
local _crg_main="${TWILL_REPO_ROOT}/main/.code-review-graph"
```

`effective_project_dir` の代わりに `TWILL_REPO_ROOT` を使用。`ISSUE_REPO_PATH` 設定時も twill の CRG DB を参照する（クロスリポの CRG 対応は別 Issue）。

### D3: `_is_main` 判定の簡素化

```bash
local _normalized_wt="${worktree_dir%/}"
local _normalized_main="${TWILL_REPO_ROOT}/main"
local _is_main=0
[[ "$_normalized_wt" == "$_normalized_main" ]] && _is_main=1
```

`realpath` 呼び出しを廃止し、文字列比較に変更。末尾スラッシュを strip することで誤検知を防ぐ。

## Risks / Trade-offs

- **TWILL_REPO_ROOT 未設定環境**: `PROJECT_DIR` が空の場合は `TWILL_REPO_ROOT` も空になる。ただし `PROJECT_DIR` は orchestrator 起動時に必須チェックされているため、実質的なリスクは低い
- **クロスリポ CRG**: `ISSUE_REPO_PATH` 設定時に当該リポの CRG DB を参照できないが、それは本 Issue スコープ外。将来的な拡張ポイントとして残す
