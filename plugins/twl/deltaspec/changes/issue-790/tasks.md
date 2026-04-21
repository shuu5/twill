# Tasks: chain.py SSoT refinement (Issue #790)

## Phase 0: Pre-flight（必須、実装前）

- [ ] **T0.1** W1 #785 (workflow_done 除去) のマージ完了を確認
- [ ] **T0.2** `rg 'board-status-update' -t py -t sh -t yaml -t md` で全参照を洗い出し、該当行リストを PR 説明に記載
- [ ] **T0.3** `rg 'CHAIN_STEP_DISPATCH|CHAIN_STEP_WORKFLOW|CHAIN_WORKFLOW_NEXT_SKILL' plugins/twl/scripts/` で bash 側 SSoT 参照箇所を確認

## Phase 1: chain.py 改名 + CHAIN_META 追加

- [ ] **T1.1** `cli/twl/src/twl/autopilot/chain.py`
  - L31 `"board-status-update"` → `"project-board-status-update"`
  - L72 同上
  - `CHAIN_META: dict[str, dict[str, str]]` を CHAIN_STEPS の直後に追加（design.md の全 30 step を列挙）
  - `STEP_TO_WORKFLOW` を CHAIN_META 由来の dict comprehension に変換
  - `step_board_status_update()` メソッド内の `self.record_step(issue_num, "board-status-update")` を `"project-board-status-update"` に改名
- [ ] **T1.2** `plugins/twl/scripts/chain-runner.sh`
  - L1497-1498 の `board-status-update) step_board_status_update "$@" ;;` 行を削除
  - L1498 の `project-board-status-update)` を単行化
  - L430 `record_current_step "board-status-update"` を `"project-board-status-update"` に改名
  - L1458, L1532 の usage 表示から `board-status-update` を削除
- [ ] **T1.3** `cli/twl/src/twl/autopilot/mergegate_guards.py` 等 `board-status-update` 文字列参照箇所を修正（T0.2 で洗い出した箇所）
- [ ] **T1.4** `pytest cli/twl/tests/test_autopilot_chain.py` 単体テスト更新 + PASS
- [ ] **T1.5** `bats plugins/twl/tests/bats/scripts/chain-runner-next-step.bats` 期待値更新 + PASS

## Phase 2: export API 実装

- [ ] **T2.1** `cli/twl/src/twl/autopilot/chain.py`
  - `export_deps_chains() -> dict` 実装
  - `export_chain_steps_sh() -> str` 実装
  - YAML ラウンドトリップで既存 deps.yaml の他セクション（components 等）保持
- [ ] **T2.2** `cli/twl/src/twl/chain/export.py` 新規作成
  - argparse で `--yaml` / `--shell` / `--dry-run` / `--check` (= byte-diff 検証) フラグ
  - `--yaml`: deps.yaml を YAML ロード → chains/meta_chains 差し替え → dump
  - `--shell`: `export_chain_steps_sh()` の文字列を chain-steps.sh に書込
- [ ] **T2.3** `cli/twl/src/twl/cli.py` L74-88 付近の `chain` subcommand dispatch に `export` 分岐を追加
- [ ] **T2.4** `cli/twl/tests/test_autopilot_chain_export.py` 新規作成
  - `export_deps_chains()` が現行 deps.yaml.chains と dict-level 等価
  - `export_chain_steps_sh()` が現行 chain-steps.sh と byte-identical
- [ ] **T2.5** `twl chain export --yaml --dry-run` と `twl chain export --shell --dry-run` が byte-identical (= diff ゼロ) を CI で検証

## Phase 3: feature flag 統合

- [ ] **T3.1** `plugins/twl/scripts/chain-runner.sh` L17 を env-conditional に変更:
  ```bash
  if [[ "${TWL_CHAIN_SSOT_MODE:-deps.yaml}" == "chain.py" ]]; then
    eval "$(twl chain export --shell)"
  else
    source "${SCRIPT_DIR}/chain-steps.sh"
  fi
  ```
- [ ] **T3.2** `plugins/twl/tests/bats/scripts/chain-runner-ssot-mode.bats` 新規作成
  - `TWL_CHAIN_SSOT_MODE=chain.py bash chain-runner.sh next-step 0 init` → `project-board-status-update`
  - `TWL_CHAIN_SSOT_MODE=deps.yaml bash chain-runner.sh next-step 0 init` → 同値
  - `bash chain-runner.sh next-step 0 init`（env 未設定）→ 同値（default fallback 動作）
  - `bash chain-runner.sh board-status-update <args>` → 未知ステップエラー（alias 削除検証）

## Phase 4: 整合性検証拡張

- [ ] **T4.1** `cli/twl/src/twl/chain/validate.py`
  - chain.py `CHAIN_STEPS ∪ CHAIN_META.keys()` == deps.yaml.chains 全 steps set（差分ゼロ）
  - CHAIN_META[step].dispatch_mode == deps.yaml components[step].dispatch_mode（各 step）
  - chain-steps.sh が `twl chain export --shell` 出力と byte-identical
- [ ] **T4.2** `cli/twl/tests/test_chain_validate.py` 拡張

## Phase 5: 非回帰検証（AC 6項目）

- [ ] **T5.1** `twl --check` PASS
- [ ] **T5.2** `pytest cli/twl/tests/` 全 PASS
- [ ] **T5.3** `bash plugins/twl/tests/bats/run.sh` 全 PASS
- [ ] **T5.4** `bash plugins/twl/tests/scenarios/chain-definition.test.sh` PASS
- [ ] **T5.5** `TWL_CHAIN_SSOT_MODE=chain.py bash plugins/twl/scripts/chain-runner.sh next-step 0 init` が `project-board-status-update` を返す
- [ ] **T5.6** `twl chain export --yaml --dry-run` / `twl chain export --shell --dry-run` が diff ゼロ

## Phase 6: ADR マージ + Issue body 更新

- [ ] **T6.1** `plugins/twl/architecture/decisions/ADR-020-chain-ssot-refinement.md` Status: Proposed → Accepted に更新（本 PR マージ後）
- [ ] **T6.2** Issue #790 body の Critical Files / AC を proposal.md の「Acceptance Criteria (Issue body 修正案)」セクションに合わせて更新（observer が実装時適用）
- [ ] **T6.3** refined ラベル再付与（specialist review PASS 後）

## Out of scope (follow-up Issues)

- **#791 deps-integrity**: pre-commit hook で `twl chain export --yaml --check` 自動実行
- **chain-steps.sh 完全廃止**: Wave 完了後 + `TWL_CHAIN_SSOT_MODE` default 切替
- **`twl check` の deps 整合性拡張**: ADR-0007 継承 TODO
