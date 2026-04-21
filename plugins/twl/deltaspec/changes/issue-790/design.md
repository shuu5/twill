# Design: chain.py SSoT refinement (Issue #790)

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        chain.py (SSoT)                           │
│                                                                  │
│   CHAIN_STEPS:   [runner dispatch の機械的順序]                  │
│   CHAIN_META:    {step: {chain, dispatch_mode, ...}}             │
│   STEP_TO_WORKFLOW (derived from CHAIN_META)                     │
│   TERMINAL_STEP_TO_NEXT_SKILL (存続)                             │
│                                                                  │
│   export_deps_chains()  -> dict                                  │
│   export_chain_steps_sh() -> str                                 │
└──────────────────────────────────────────────────────────────────┘
                │                          │
                ▼                          ▼
    ┌───────────────────┐      ┌────────────────────────┐
    │ deps.yaml         │      │ chain-steps.sh         │
    │ (computed)        │      │ (computed)             │
    │                   │      │                        │
    │  chains:          │      │  CHAIN_STEPS=(...)     │
    │  meta_chains:     │      │  QUICK_SKIP_STEPS=(...) │
    │                   │      │  CHAIN_STEP_DISPATCH   │
    │  他セクション保持 │      │  CHAIN_STEP_WORKFLOW   │
    └───────────────────┘      └────────────────────────┘
                                          │
                                          ▼
                             ┌────────────────────────┐
                             │ chain-runner.sh        │
                             │                        │
                             │  if TWL_CHAIN_SSOT_MODE│
                             │     == "chain.py":     │
                             │    eval "$(twl chain   │
                             │      export --shell)"  │
                             │  else:                 │
                             │    source chain-steps  │
                             └────────────────────────┘
```

## データ構造

### CHAIN_META（新設）

```python
CHAIN_META: dict[str, dict[str, str]] = {
    # setup chain
    "init":                       {"chain": "setup",      "dispatch_mode": "runner"},
    "worktree-create":            {"chain": "setup",      "dispatch_mode": "trigger"},
    "project-board-status-update":{"chain": "setup",      "dispatch_mode": "trigger"},
    "crg-auto-build":             {"chain": "setup",      "dispatch_mode": "llm"},
    "change-propose":             {"chain": "setup",      "dispatch_mode": "llm"},
    "ac-extract":                 {"chain": "setup",      "dispatch_mode": "runner"},

    # test-ready chain
    "arch-ref":                   {"chain": "test-ready", "dispatch_mode": "runner"},
    "change-id-resolve":          {"chain": "test-ready", "dispatch_mode": "runner"},
    "test-scaffold":              {"chain": "test-ready", "dispatch_mode": "llm"},
    "check":                      {"chain": "test-ready", "dispatch_mode": "runner"},
    "change-apply":               {"chain": "test-ready", "dispatch_mode": "llm"},
    "post-change-apply":          {"chain": "test-ready", "dispatch_mode": "runner"},

    # pr-verify chain
    "prompt-compliance":          {"chain": "pr-verify",  "dispatch_mode": "runner"},
    "ts-preflight":               {"chain": "pr-verify",  "dispatch_mode": "runner"},
    "phase-review":               {"chain": "pr-verify",  "dispatch_mode": "llm"},
    "scope-judge":                {"chain": "pr-verify",  "dispatch_mode": "llm"},
    "pr-test":                    {"chain": "pr-verify",  "dispatch_mode": "runner"},
    "ac-verify":                  {"chain": "pr-verify",  "dispatch_mode": "llm"},

    # pr-fix chain
    "fix-phase":                  {"chain": "pr-fix",     "dispatch_mode": "llm"},
    "post-fix-verify":            {"chain": "pr-fix",     "dispatch_mode": "llm"},
    "warning-fix":                {"chain": "pr-fix",     "dispatch_mode": "llm"},

    # pr-merge chain
    "e2e-screening":              {"chain": "pr-merge",   "dispatch_mode": "llm"},
    "pr-cycle-report":            {"chain": "pr-merge",   "dispatch_mode": "runner"},
    "pr-cycle-analysis":          {"chain": "pr-merge",   "dispatch_mode": "llm"},
    "all-pass-check":             {"chain": "pr-merge",   "dispatch_mode": "runner"},
    "merge-gate":                 {"chain": "pr-merge",   "dispatch_mode": "llm"},
    "auto-merge":                 {"chain": "pr-merge",   "dispatch_mode": "trigger"},

    # arch-review chain
    "arch-phase-review":          {"chain": "arch-review", "dispatch_mode": "llm"},
    "arch-fix-phase":             {"chain": "arch-review", "dispatch_mode": "llm"},
}
```

**注記**:
- `CHAIN_STEPS` は本質的に `CHAIN_META` の subset (dispatch_mode=runner のみ、ただし既存 `ac-verify`/`phase-review` 等の LLM マーカー含む) だが、`next_step()` の挙動を保つため別リストを維持
- migration フェーズで `CHAIN_STEPS` を `CHAIN_META` から derive する setup は Wave 完了後の refactor で対応

### STEP_TO_WORKFLOW の CHAIN_META からの生成

```python
# 現状: chain.py L70-90 に static dict
# 移行後: 下記に置換
STEP_TO_WORKFLOW: dict[str, str] = {
    step: {
        "setup": "setup",
        "test-ready": "test-ready",
        "pr-verify": "pr-verify",
        "pr-fix": "pr-fix",
        "pr-merge": "pr-merge",
        "arch-review": "arch-review",
    }[meta["chain"]]
    for step, meta in CHAIN_META.items()
}
```

## 変更点サマリ

### chain.py

| 変更 | 詳細 |
|---|---|
| CHAIN_STEPS L31 改名 | `board-status-update` → `project-board-status-update` |
| STEP_TO_WORKFLOW L72 改名 | 同上 |
| CHAIN_META 追加 | 全 step の {chain, dispatch_mode} を管理 |
| STEP_TO_WORKFLOW 生成化 | static dict を CHAIN_META からの dict comprehension に置換 |
| `export_deps_chains()` 追加 | deps.yaml.chains / meta_chains セクション生成 |
| `export_chain_steps_sh()` 追加 | chain-steps.sh bash ソース生成 |
| `step_board_status_update` メソッド名 | 関数内部名は保持（呼出ラベルのみ改名） |

### chain-runner.sh

| 変更 | 詳細 |
|---|---|
| L17 env-conditional | `if TWL_CHAIN_SSOT_MODE == chain.py` 分岐追加 |
| L1497-1498 alias 削除 | `board-status-update)` 行を削除、`project-board-status-update` 単行化 |
| L430 record_current_step | `"board-status-update"` → `"project-board-status-update"` |
| L1458, L1532 usage 表示 | 名称統一 |

### chain-steps.sh

`export_chain_steps_sh()` の出力で置換（L10-122 全体）。

### deps.yaml

`export_deps_chains()` の出力で `chains:` (L26-84) / `meta_chains:` (L87-152) を置換。他セクション（components 等）は YAML ラウンドトリップで保持。

### cli.py

```python
# L74-88 付近の chain subcommand dispatch に追加
elif len(sys.argv) >= 3 and sys.argv[2] == 'export':
    from twl.chain.export import handle_chain_export
    sys.exit(handle_chain_export(sys.argv[3:]))
```

新規: `cli/twl/src/twl/chain/export.py` (argparse + writer)

## テスト計画

### 新規テスト

1. `cli/twl/tests/test_autopilot_chain_export.py`
   - `export_deps_chains()` が既存 deps.yaml.chains と dict-level で等価
   - `export_chain_steps_sh()` が既存 chain-steps.sh と byte-identical
   - CHAIN_META と STEP_TO_WORKFLOW の整合性（dict comprehension invariant）
2. `plugins/twl/tests/bats/scripts/chain-runner-ssot-mode.bats`
   - `TWL_CHAIN_SSOT_MODE=chain.py` で `next-step 0 init` が `project-board-status-update` を返す
   - `TWL_CHAIN_SSOT_MODE=deps.yaml`（または unset）で同等動作
   - alias 削除後 `board-status-update` 引数で未知ステップエラーを返す
3. `cli/twl/tests/test_chain_validate.py` 拡張
   - chain.py `CHAIN_STEPS + CHAIN_META` set == deps.yaml.chains 全 steps set
   - `dispatch_mode` の roundtrip 整合

### 既存テスト更新

1. `plugins/twl/tests/bats/scripts/chain-runner-next-step.bats` — `board-status-update` 期待値更新
2. `plugins/twl/tests/scenarios/chain-definition.test.sh` — 名称統一前提で再実行
3. `cli/twl/tests/test_autopilot_chain.py` — CHAIN_STEPS 改名反映

## Migration Path

1. **Pre-flight** (Wave 3 着手前、別 quick Issue または本 Issue の第一タスク)
   - `rg 'board-status-update'` で全参照洗い出し
   - W1 #785 (workflow_done 除去) 完了確認

2. **Phase 1**: chain.py 改名 + CHAIN_META 追加（機能等価、コードレベル）
   - chain.py 変更 → chain-runner.sh alias 削除
   - bats / pytest 全 PASS

3. **Phase 2**: export API + CLI 統合（機能追加、後方互換）
   - `export_deps_chains()` / `export_chain_steps_sh()` 実装
   - `twl chain export --yaml --dry-run` が現行 deps.yaml と byte-identical（diff ゼロ）
   - `twl chain export --shell --dry-run` が現行 chain-steps.sh と byte-identical

4. **Phase 3**: feature flag 統合
   - chain-runner.sh 冒頭 env check 追加
   - `TWL_CHAIN_SSOT_MODE=chain.py` 経路を bats で検証
   - default は `deps.yaml`

5. **Phase 4** (Wave 終盤、別 Issue)
   - `TWL_CHAIN_SSOT_MODE=chain.py` を default に切替
   - 本 Issue の AC 完了後、chain-steps.sh を pre-commit で自動再生成するゲート設置（→ #791）

## Rollback

- chain.py 改名 revert: `git revert <commit>` + alias 再追加
- feature flag default=`deps.yaml` なので、emergency 時は env を明示しないだけで従来動作
- deps.yaml export 結果が不整合の場合、`git checkout HEAD~1 plugins/twl/deps.yaml` で戻し

## 未決事項（本 change では扱わない）

- pre-commit hook での `twl chain export --yaml --check` 自動実行 → #791 の責務
- chain-steps.sh の完全廃止 → Wave 完了後 + `TWL_CHAIN_SSOT_MODE` default 切替後
- `twl check` の deps 整合性拡張 → 別 Issue (ADR-0007 の継承 TODO)
