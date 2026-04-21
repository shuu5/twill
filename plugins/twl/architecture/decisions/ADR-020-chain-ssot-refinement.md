# ADR-020: chain SSoT refinement — chain.py を真の SSoT 化する具体手順

**Status**: Proposed
**Date**: 2026-04-21
**Issue**: #790
**Supersedes**: —
**Related**: ADR-0007 (chain SSOT 2 レイヤー責務分離)、ADR-018 (state schema SSoT)、ADR-021 (pilot-driven workflow loop)

---

## Context

ADR-0007 で「chain.py が chain 定義の SSoT、deps.yaml.chains は概念レイヤー、chain-steps.sh は chain.py の bash 向けミラー」と決定された。しかし以下の残存問題がある:

1. **名称不一致**: chain.py L31 `board-status-update` vs deps.yaml/chain-steps.sh `project-board-status-update`。`commands/project-board-status-update.md` が実在し、deps.yaml の正規名。chain-runner.sh (L1497-1498) は両名をエイリアスで救済しており、実行は破綻していないが SSoT として未整合。
2. **CHAIN_STEPS 非保有ステップ**: `dispatch_mode: llm|trigger` のステップ（`worktree-create`, `e2e-screening`, `merge-gate`, `auto-merge`, `fix-phase`, `post-fix-verify`, `warning-fix`, `arch-phase-review`, `arch-fix-phase`, `pr-cycle-analysis`）が deps.yaml.chains にのみ存在。ADR-0007 の方針では CHAIN_STEPS に含めないことが正だが、chain.py は dispatch や workflow 所属を認識しないため export 時にメタデータを再生成できない。
3. **CHAIN_STEP_DISPATCH のミラーリング方向**: chain-steps.sh L55-75 の dispatch 定義が SSoT として扱われているが、ADR-0007 に従えば chain.py 側に帰属させるべき。
4. **feature flag 未実装**: `TWL_CHAIN_SSOT_MODE` は Issue 本文で AC 化されているが、env 検査層が未定義。

## Decision

### D-1: 名称の正規化 — chain.py を deps.yaml 正規名に寄せる

chain.py の以下 3 箇所を `project-board-status-update` に改名する:

- `CHAIN_STEPS` L31
- `STEP_TO_WORKFLOW` L72
- （`TERMINAL_STEP_TO_NEXT_SKILL` は `board-status-update` を含まないため変更不要）

合わせて:

- chain-runner.sh L1497-1498 の alias 分岐を廃止 (`project-board-status-update) step_board_status_update "$@" ;;` 単一行に)
- 関数名 `step_board_status_update` は関数内部名として保持可（dispatch 名と関数名は別責務）
- chain.py の `step_board_status_update` メソッドも関数内部名として保持可
- 呼び出し側 (`record_step`, `_ok`, `_skip`) に渡すラベル文字列を `project-board-status-update` に統一
- ログ・トレース文字列検索で `board-status-update` 残存が発生しないことを `rg` で確認

**根拠**: ADR-0007 の「chain.py が SSoT」原則を maintain しつつ、deps.yaml コンポーネント正規名（`commands/project-board-status-update.md` が実ファイル）に合わせる。alias 廃止により drift 再発源が消える。

### D-2: CHAIN_META データ構造導入

chain.py に新しい dict `CHAIN_META` を追加:

```python
CHAIN_META: dict[str, dict[str, str]] = {
    # runner dispatch (既存 CHAIN_STEPS と重複。dispatch_mode 補足用)
    "init": {"chain": "setup", "dispatch_mode": "runner"},
    "project-board-status-update": {"chain": "setup", "dispatch_mode": "trigger"},
    ...
    # llm dispatch (CHAIN_STEPS 非保有、deps.yaml.chains のみ)
    "e2e-screening":    {"chain": "pr-merge",  "dispatch_mode": "llm"},
    "merge-gate":       {"chain": "pr-merge",  "dispatch_mode": "llm"},
    "pr-cycle-analysis":{"chain": "pr-merge",  "dispatch_mode": "llm"},
    "fix-phase":        {"chain": "pr-fix",    "dispatch_mode": "llm"},
    "post-fix-verify":  {"chain": "pr-fix",    "dispatch_mode": "llm"},
    "warning-fix":      {"chain": "pr-fix",    "dispatch_mode": "llm"},
    "arch-phase-review":{"chain": "arch-review","dispatch_mode": "llm"},
    "arch-fix-phase":   {"chain": "arch-review","dispatch_mode": "llm"},
    # trigger dispatch (chain 外の条件付き実行)
    "worktree-create":  {"chain": "setup",     "dispatch_mode": "trigger"},
    "auto-merge":       {"chain": "pr-merge",  "dispatch_mode": "trigger"},
}
```

**責務**:

- `CHAIN_STEPS` は `next-step` で返す「runner dispatch の機械的順序」のみ（既存設計保持）
- `CHAIN_META` は dispatch/chain 所属の正典（export 時に deps.yaml.chains の dispatch_mode と chain: を再生成）
- chain-steps.sh の `CHAIN_STEP_DISPATCH` / `CHAIN_STEP_WORKFLOW` は `export_chain_steps_sh()` が `CHAIN_META` から再生成

### D-3: export API

chain.py に以下を追加:

```python
def export_deps_chains() -> dict[str, Any]:
    """Return the `chains:` section for deps.yaml."""
    # chain_id ごとに steps 順を CHAIN_STEPS (runner) + CHAIN_META (llm/trigger) から合成
    # 出力フォーマットは既存 deps.yaml の chains: を忠実に再現

def export_chain_steps_sh() -> str:
    """Return chain-steps.sh bash source as string."""
    # CHAIN_STEPS, QUICK_SKIP_STEPS, DIRECT_SKIP_STEPS,
    # CHAIN_STEP_DISPATCH, CHAIN_STEP_WORKFLOW, CHAIN_WORKFLOW_NEXT_SKILL
    # を CHAIN_META と STEP_TO_WORKFLOW から再生成
```

CLI 統合（feasibility HIGH 85 指摘の必須修正）:

- `cli/twl/src/twl/cli.py` L74-88 の `chain` subcommand dispatch に `export` 分岐を追加
- `twl chain export --yaml` → `plugins/twl/deps.yaml` の `chains:` / `meta_chains:` セクションを再生成（他セクション保持、YAML ラウンドトリップで整合）
- `twl chain export --shell` → `plugins/twl/scripts/chain-steps.sh` を再生成

### D-4: feature flag の読取層

chain-runner.sh 冒頭 (L17 `source chain-steps.sh`) を env-conditional に変更:

```bash
if [[ "${TWL_CHAIN_SSOT_MODE:-deps.yaml}" == "chain.py" ]]; then
  eval "$(twl chain export --shell)"
else
  # shellcheck source=./chain-steps.sh
  source "${SCRIPT_DIR}/chain-steps.sh"
fi
```

**責務分離**:
- chain.py は env を読まない（値の提供者としてピュア）
- chain-runner.sh が runtime の dispatch 選択を行う
- Wave 完了後 (= `chain.py` モードが安定) に `TWL_CHAIN_SSOT_MODE` 自体を撤去し chain.py 経由を default 化

### D-5: 整合性検証の強化

`twl chain validate` を以下で拡張:

- chain.py `CHAIN_STEPS` + `CHAIN_META` の set == deps.yaml.chains 全 steps の set（差分ゼロ）
- chain.py `CHAIN_META[step].dispatch_mode` == deps.yaml components の `dispatch_mode`（export-roundtrip 整合）
- chain-steps.sh が `twl chain export --shell` 出力と byte-identical

## Consequences

### 利点

- chain drift が「export で常に再生成」により機械的に解消
- alias 層消失で名称ドリフトの再発源除去
- CHAIN_META 追加により LLM/trigger ステップの chain 所属・dispatch が SSoT 化
- feature flag で段階的ロールアウトが可能

### 懸念 / 代償

- 既存コード中の `board-status-update` 文字列参照を洗い出す必要 (`rg 'board-status-update'` で事前確認)
- `twl chain export` CLI 追加は `cli.py` / `cli_dispatch.py` の変更を伴う（Critical Files に追加が必要）
- Wave 完了後 `TWL_CHAIN_SSOT_MODE` を撤去するフォロー Issue が必要（本 Issue のスコープ外）

### ロールバック手順

- `TWL_CHAIN_SSOT_MODE=deps.yaml`（default）で従来動作に戻る
- chain.py 改名を revert 不要な setup に保ち、alias 追加で戻せる（ただし Wave 中は alias 再追加を避ける）

## Non-goal

- pre-commit / CI ゲート統合は `#791 (deps-integrity)` の責務（本 ADR から除外）
- `twl check` の deps 整合性検証追加は別 Issue（ADR-0007 の TODO 継承）
- chain-steps.sh の完全廃止は Wave 完了後の別 Issue（この ADR は chain-steps.sh を `computed artifact` 化するまでを扱う）
