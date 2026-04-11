## Context

`twl spec new` は `find_deltaspec_root()` が失敗した場合（`DeltaspecNotFound`）に cwd 直下へ silent auto-init する。モノリポ移行（#435）以降、worktree 内に `plugins/twl/deltaspec/config.yaml` / `cli/twl/deltaspec/config.yaml` が存在するが、#435 merge 前に分岐した feat branch にはこれらが存在しない。その結果、walk-up/walk-down 両方が失敗し auto-init が誤発動する。修正範囲は `cli/twl/src/twl/spec/` と `plugins/twl/scripts/chain-runner.sh` の計 4 箇所。AC-4（archive multi-root）は #460 ブロック待ちのため本 Issue では扱わない。

## Goals / Non-Goals

**Goals:**
- `DeltaspecNotFound` 時に auto-init を抑制し、原因と対処法を含むエラーを返す（AC-1 Phase 1）
- 移行期間中の旧 branch 継続のため `TWL_SPEC_ALLOW_AUTO_INIT=1` で従来動作を維持（AC-1 Phase 2）
- `find_deltaspec_root()` のエラーメッセージに試行パス一覧と rebase 推奨を追加（AC-2）
- `step_init` で nested config.yaml 欠落時に WARN + rebase 促進メッセージを出力（AC-3）
- unit test と bats scenario を追加（AC-6）

**Non-Goals:**
- AC-4（archive multi-root） — #460 で `lib/deltaspec-helpers.sh` 切り出し後に実装
- AC-5（既存 orphan 手動移動）— 本 PR 範囲外。別コマンドまたは手動実施
- `TWL_SPEC_ALLOW_AUTO_INIT` の完全廃止（Phase 3）— 別 Issue で追跡

## Decisions

### D-1: auto-init 抑制の判定ロジック（AC-1 Phase 1）

`new.py` の `except DeltaspecNotFound` ブロックで以下を実行:

```python
import subprocess, os, sys

# origin/main に nested config.yaml が存在するか確認
result = subprocess.run(
    ["git", "ls-tree", "-r", "--name-only", "origin/main"],
    capture_output=True, text=True, cwd=Path.cwd()
)
has_remote_nested = any(
    "deltaspec/config.yaml" in line
    for line in result.stdout.splitlines()
    if line != "deltaspec/config.yaml"  # worktree-root 直下を除く
)

if has_remote_nested and not os.environ.get("TWL_SPEC_ALLOW_AUTO_INIT"):
    # Phase 1: nested root が origin/main に存在 → rebase 未実施
    print("Error: nested deltaspec root が origin/main に存在しますが...", file=sys.stderr)
    return 1
elif not os.environ.get("TWL_SPEC_ALLOW_AUTO_INIT") and not has_remote_nested:
    # 純粋な新規プロジェクト: git ls-tree が使えない場合も含む
    # 引き続き auto-init（Phase 1 対象外）
    pass
```

`origin/main` へのアクセスが失敗した場合（offline, 未設定）は WARN を出して従来の auto-init にフォールバックする（可用性優先）。

**代替案**: `find_deltaspec_root()` の返り値を拡張して tried_paths を持つ `Result` 型にする案は API 変更が大きく他コマンドへの影響が広いため採用しない。

### D-2: `find_deltaspec_root()` エラーメッセージ強化（AC-2）

`paths.py` の `DeltaspecNotFound` 例外に tried_paths 引数を追加し、raise 元で試行パスを記録:

```python
raise DeltaspecNotFound(
    "deltaspec/config.yaml not found.\n"
    f"  Walked up from: {start_path}\n"
    f"  Searched git root: {git_top or '(no .git found)'}\n"
    "  Hint: feat branch が origin/main より古い場合は `git rebase origin/main` を実行してください。"
)
```

### D-3: `step_init` rebase ガード（AC-3）

`chain-runner.sh` の `step_init` 関数冒頭（ブランチ判定の前）に以下を追加:

```bash
# Nested deltaspec config.yaml の存在チェック（#435 以降の rebase 確認）
_check_nested_deltaspec_configs() {
  local root="$1"
  local missing=()
  for cfg in "plugins/twl/deltaspec/config.yaml" "cli/twl/deltaspec/config.yaml"; do
    [[ ! -f "$root/$cfg" ]] && missing+=("$cfg")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "init" "nested deltaspec config が見つかりません: ${missing[*]}"
    warn "init" "この branch は origin/main より古い可能性があります。'git rebase origin/main' を推奨します"
  fi
}
_check_nested_deltaspec_configs "$root"
```

WARN のみ。abort はしない（手動セッション中断を避けるため）。

### D-4: unit test 追加（AC-6）

`cli/twl/tests/spec/test_new.py` に以下を追加:
- nested root 存在時（`origin/main` に config.yaml あり）: auto-init が発動せずエラーを返す
- `TWL_SPEC_ALLOW_AUTO_INIT=1` 設定時: 従来の auto-init が動作する
- `origin/main` アクセス失敗（offline）: WARN してフォールバック

bats scenario の配置場所は `cli/twl/tests/scenarios/` または `plugins/twl/tests/` の既存パターンに従う。

## Risks / Trade-offs

- **`git ls-tree origin/main` の実行コスト**: `twl spec new` は毎回 1 回のみ呼ばれるため許容範囲。ただしネットワーク不要（ローカルの git object から読む）。
- **`origin/main` が存在しない環境**: offline 開発や fork-only 環境では `git ls-tree` が失敗する。D-1 の通り WARN + フォールバックで対処。
- **AC-3 の WARN を無視したまま作業継続**: abort ではなく WARN にとどめるため、誤った cwd での `twl spec new` は依然として実行できる。しかし Phase 1 の auto-init 抑制（D-1）により worktree root への誤作成は防げる。
- **change-propose.md の auto_init 条件**: `DELTASPEC_EXISTS=false` 判定は Python レベルの fix（D-1）と整合する形で文言を更新する（nested root 欠如 ≠ deltaspec 未初期化）。
