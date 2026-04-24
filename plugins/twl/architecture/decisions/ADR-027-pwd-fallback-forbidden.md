# ADR-027: resolve_project_root() での pwd フォールバック禁止

**Status**: Accepted
**Date**: 2026-04-25
**Issue**: #966

## Context

`plugins/twl/scripts/chain-runner.sh` の `resolve_project_root()` は `git rev-parse --show-toplevel 2>/dev/null || pwd` というシンプルな実装だった。`git rev-parse` 失敗時に `|| pwd` でカレントワーキングディレクトリ（CWD）を project root として採用していた。

Wave AA.3（2026-04-24）の Phase 1 で以下の permission prompt が発火した:

```
Bash command: mkdir -p /home/shuu5/.claude/plugins/twl/.dev-session/issue-955
Claude requested permissions to edit /home/shuu5/.claude/plugins/twl/.dev-session/issue-955
which is a sensitive file.
```

期待される書き込み先は `<worktree>/.dev-session/issue-955/` だが、Worker の CWD が git 管理外のパスになった場合、`|| pwd` フォールバックがその CWD を root として採用し、user-global 領域へ誤書き込みする危険があった。doobidoo hash `b81b1962` に詳細を記録済み。

`resolve_project_root()` は chain-runner.sh 内の 7 つの呼出点（L231/L406/L475/L712/L794/L1227/L1241）で使われており、誤 root 採用による副作用は `.dev-session/` 書き込みから `cd "$root"` によるディレクトリ変更まで幅広い。

## Decision

`resolve_project_root()` に 3 段 fallback を採用し、`pwd` フォールバックを構造的に撤廃する:

```bash
resolve_project_root() {
  local root
  # tier 1: 現 CWD から rev-parse
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
  if [[ -n "$root" ]]; then
    echo "$root"
    return 0
  fi
  # tier 2: script 位置から rev-parse（Worker CWD が git 管理外でも救済）
  local script_root
  script_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || script_root=""
  if [[ -n "$script_root" ]]; then
    echo "$script_root"
    return 0
  fi
  # tier 3: fallback 失敗 → stderr + return 1（pwd 誤採用を構造的に不可能化）
  echo "[chain-runner] FATAL: resolve_project_root failed (cwd=$(pwd), script=${BASH_SOURCE[0]})" >&2
  return 1
}
```

| tier | trigger 条件 | 救済対象 |
|---|---|---|
| 1 (primary) | CWD が git worktree 内 | 通常動作 |
| 2 (script-path) | CWD が git 管理外 だが script は worktree 内 | Worker CWD が `/tmp` 等に逸脱してもスクリプトが symlink 経由で worktree 内に常駐していれば救済 |
| 3 (fail-fast) | script 自体も worktree 外に配置 | 明示的 error で誤動作を構造的に防止 |

## Consequences

**Positive**:
- `|| pwd` による user-global 書き込みが構造的に不可能化される
- tier 3 の `return 1` により、呼出点の `set -euo pipefail` が fail-fast を発動し、誤 root での後続書き込みを防止できる
- tier 2 は `~/.claude/plugins/twl/scripts/` symlink → `main/plugins/twl/scripts/` → git rev-parse で実測救済可能（verified）

**Negative**:
- tier 3 発動時に Worker が abort する。ただし誤 root での副作用よりはるかに安全
- script が worktree 外に配置される異常状態（tier 3 が唯一の出口）は想定外の運用に対応できないが、現行設計では script は常に worktree 内 symlink 経由で配置される

## Alternatives Considered

**(a) `exit 1` 単独**: caller 修正コストが高い。fallback なしで legitimate Worker CWD 逸脱で即死するため UX が悪い。却下。

**(b) `git worktree list --porcelain` fallback 単独**: Phase 4 specialist 検証で判明 — `cd /tmp && git worktree list --porcelain` は `fatal: not a git repository`, exit 128 で失敗する。tier 1 が fail する状況では同条件で fail するため dead code。却下。

**(c) 本 Decision = script-path fallback**: `(cd ~/.claude/plugins/twl/scripts && git rev-parse --show-toplevel)` が `main` worktree を返すことを実測確認済み。CWD が完全に非 git でも救済可能。採用。

## References

- Issue #966: `resolve_project_root()` の pwd フォールバック撤廃
- Issue #938: per-issue namespace（`.dev-session/issue-N/`）実装（直接の動機）
- doobidoo `b81b1962`: Wave AA.3 Phase 1 permission prompt 発火記録
- `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md` §14
