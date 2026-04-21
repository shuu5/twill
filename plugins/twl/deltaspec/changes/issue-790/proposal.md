# Proposal: chain.py SSoT refinement (Issue #790)

## Summary

ADR-0007 の「chain.py が chain 定義の SSoT」方針を具体的な export API / CHAIN_META / 名称統一に落とし込み、`deps.yaml.chains` と `chain-steps.sh` を chain.py から生成される `computed artifact` 化する。

参照: ADR-020（本 change と同時提案）

## Goals

1. **名称ドリフトの根治**: chain.py の `board-status-update` を `project-board-status-update` に改名し、chain-runner.sh の alias 層を廃止する
2. **CHAIN_META の導入**: LLM/trigger dispatch のステップ（CHAIN_STEPS 非保有）も chain.py で SSoT 管理
3. **export API**: `twl chain export --yaml` / `--shell` で deps.yaml / chain-steps.sh を再生成
4. **feature flag**: `TWL_CHAIN_SSOT_MODE` を chain-runner.sh 冒頭で判定し段階ロールアウト

## Non-goals

- pre-commit / CI 整合性ゲート（→ #791）
- `twl check` の deps 整合性チェック拡張（別 Issue）
- chain-steps.sh の完全廃止（Wave 完了後）
- workflow_done 完全除去（W1 #785 が先行）

## Alternatives considered

| 選択肢 | 採否 | 理由 |
|---|---|---|
| Q-A A-1': chain.py を改名 | **採用** | ADR-0007 (chain.py SSoT) 維持 + deps.yaml 正規名整合 |
| Q-A A-2: deps.yaml を board-status-update に改名 | 不採用 | ADR-0007 と matrix 整合、ファイル名変更コスト高 |
| Q-A A-3: export に mapping 追加 | 不採用 | 本末転倒（mapping table が新 SSoT に昇格） |
| Q-B B-3': CHAIN_META 新設 | **採用** | ADR-0007 の 2 レイヤー分離維持 + LLM/trigger の正典化 |
| Q-B B-1: 全 CHAIN_STEPS に追加 | 不採用 | ADR-0007 責務分離を破壊、quick-skip ロジック崩壊 |
| Q-B B-2: 別 Issue 化 | 不採用 | 本 Issue の SSoT 完全化が不完全になる |
| Q-C C-2: chain-runner.sh 冒頭で env check | **採用** | Python/bash 両方に影響せず fallback 経路保証 |
| Q-C C-1: chain.py 内部で env check | 不採用 | chain.py SSoT 採用後の env 意識が不自然 |
| Q-D D-1: CHAIN_META に dispatch 統合 | **採用** | SSoT 完全化、ADR-0007 準拠 |
| Q-D D-2: chain-steps.sh で手書き維持 | 不採用 | ADR-0007 の「chain-steps.sh は chain.py ミラー」と矛盾 |

## Impact

### 追加 Critical Files (Issue body 修正必要)

- `cli/twl/src/twl/cli.py` — `chain` subcommand dispatch に `export` 分岐を追加
- `cli/twl/src/twl/cli_dispatch.py` — 必要に応じて handler 統合

### 既存 Critical Files (Issue 宣言済み)

- `cli/twl/src/twl/autopilot/chain.py` — CHAIN_STEPS 名称変更 + CHAIN_META 追加 + export API
- `plugins/twl/deps.yaml` — chains / meta_chains の export 結果で置換（他セクション保持）
- `plugins/twl/scripts/chain-runner.sh` — 冒頭 env check 追加、alias 削除
- `plugins/twl/scripts/chain-steps.sh` — export 結果で置換

### 影響を受ける関連コード

- `plugins/twl/scripts/compaction-resume.sh` — chain-steps.sh を参照
- `cli/twl/src/twl/autopilot/mergegate_guards.py` — `board-status-update` 文字列参照箇所を調査
- `plugins/twl/tests/bats/scripts/chain-runner-next-step.bats` — alias 廃止で期待値更新
- `plugins/twl/tests/scenarios/chain-definition.test.sh` — 名称統一確認

### 新規テスト

- `cli/twl/tests/test_autopilot_chain_export.py` — `export_deps_chains()` / `export_chain_steps_sh()` の単体テスト
- `plugins/twl/tests/bats/scripts/chain-runner-ssot-mode.bats` — TWL_CHAIN_SSOT_MODE=chain.py / deps.yaml の両モード動作確認

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `board-status-update` 文字列参照の残存 | High | `rg 'board-status-update'` で全件洗い出し、Tasks の第一歩として実行 |
| `twl chain export --yaml` による deps.yaml 他セクション破壊 | High | YAML ラウンドトリップ ( `yaml.safe_load` → modify chains → dump ) で他セクション保持を保証、bats で diff 検証 |
| TWL_CHAIN_SSOT_MODE の意図しない早期採用 | Medium | 環境変数 default = `deps.yaml`、明示的に `chain.py` 指定したときのみ新経路 |
| CHAIN_META と既存 STEP_TO_WORKFLOW の重複 | Low | STEP_TO_WORKFLOW を CHAIN_META から自動生成する migration 経路を AC に明記 |

## Acceptance Criteria (Issue body 修正案)

本 propose 採択後、Issue #790 body の AC を以下へ更新（observer が実装時適用）:

1. **chain.py refinement**
   - `CHAIN_STEPS` 内の `board-status-update` を `project-board-status-update` に改名
   - `STEP_TO_WORKFLOW` 対応エントリを同時に改名
   - `CHAIN_META: dict[str, dict[str, str]]` を追加（dispatch_mode, chain フィールド）
   - 既存 STEP_TO_WORKFLOW は CHAIN_META から生成（重複回避）
2. **export API 追加**
   - `export_deps_chains() -> dict` — `deps.yaml.chains` / `meta_chains:` を構築（他セクション保持は CLI 層で処理）
   - `export_chain_steps_sh() -> str` — chain-steps.sh bash ソースを構築
3. **CLI 統合**
   - `cli/twl/src/twl/cli.py` L74-88 の chain subcommand に `export` を追加
   - `twl chain export --yaml` / `twl chain export --shell` の実装
4. **chain-runner.sh 統合**
   - 冒頭 `source chain-steps.sh` を `TWL_CHAIN_SSOT_MODE` 分岐に変更
   - alias `board-status-update) step_board_status_update ;;` を削除（`project-board-status-update` 単一行に）
5. **feature flag**
   - `TWL_CHAIN_SSOT_MODE=chain.py|deps.yaml` で切替（default: `deps.yaml`、Wave 完了時まで fallback）
6. **非回帰確認（既存 6 検証項目）**
   1. `twl check` PASS
   2. `pytest cli/twl/tests/` PASS
   3. `bats plugins/twl/tests/bats/` PASS
   4. `bash plugins/twl/tests/scenarios/chain-definition.test.sh` PASS
   5. `TWL_CHAIN_SSOT_MODE=chain.py bash plugins/twl/scripts/chain-runner.sh next-step 0 init` が `project-board-status-update` を返す
   6. `twl chain export --yaml --dry-run` が既存 deps.yaml と diff ゼロ（byte-identical）
7. **整合性検証**
   - `twl chain validate` を拡張（ADR-020 D-5）
8. **Critical Files に `cli/twl/src/twl/cli.py` を追加**

## 依存関係

- **blocked-by**:
  - W1 #785 (workflow_done 除去) — SSoT 候補を混乱させないため先行推奨
  - 名称統一 quick Issue (新規作成推奨、または本 Issue の第 1 タスクに包含)
- **blocks**: #8, #9, Epic #783
