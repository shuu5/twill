## Why

co-issue の Pilot 側は v1 構造のまま（Phase 2-3-4 は sequential workflow-issue-refine 呼び出し）であり、Issue #491 で整備された Worker runtime / Level-based dispatch が活用できない。本 Issue で Pilot を書き換えて v2 を実稼働させ、DAG 依存解決・並列 dispatch・aggregate/retry フローを有効化する。Feature flag `CO_ISSUE_V2` により既存パスを維持した段階移行と即時 rollback を可能にする。

## What Changes

- `plugins/twl/skills/co-issue/SKILL.md` に `## Environment` セクション（CO_ISSUE_V2 宣言）を新設
- Phase 2 を「draft 生成 → DAG 構築 → per-issue bundle 書き出し → policies.json 生成 → AskUserQuestion」に書き換え（CO_ISSUE_V2=1 フラグガード）
- Phase 3 を「Level-based dispatch（issue-lifecycle-dispatch.sh 呼び出し）→ Bash-bg wait → level_report 取得」に書き換え
- Phase 4 を「全 report.json aggregate → summary table 提示 → failure retry/accept 対話」に書き換え
- Phase 5（新規）: CO_ISSUE_V2=1 かつ 1 件以上成功時に #493 へ run log を自動投稿
- `tests/scenarios/co-issue-v2-smoke.test.sh`（新規）: flag==1 smoke テスト
- `deps.yaml`: co-issue controller の calls に workflow-issue-lifecycle を追加

## Capabilities

### New Capabilities

- **CO_ISSUE_V2 feature flag**: 環境変数でランタイム切り替え（0=旧パス維持、1=新パス有効）
- **DAG 依存解決**: draft 内 `#<local-ref>` 記法から edge 抽出 → Kahn's algorithm で topological sort → level 分割
- **Level-based dispatch**: `scripts/issue-lifecycle-dispatch.sh <sid> <level>` 呼び出し + `Bash(run_in_background=true)` wait
- **Parent URL 注入**: prev level の OUT/report.json から URL を読み出し、child policies の `parent_refs_resolved` に注入
- **Aggregate & Retry**: 全 report.json 集約 → summary table → failure 時に retry/manual/accept 選択肢
- **Soak auto-logging**: Phase 5 で #493 へ run log を gh issue comment 投稿

### Modified Capabilities

- **Phase 2**: CO_ISSUE_V2=1 分岐で DAG + bundle 書き出しパスを追加（旧パスは flag==0 で維持）
- **Phase 3**: CO_ISSUE_V2=1 分岐で issue-lifecycle-dispatch.sh 呼び出しパスを追加（旧パスは flag==0 で維持）
- **Phase 4**: CO_ISSUE_V2=1 分岐で aggregate パスを追加（旧 bulk create は flag==0 で維持）

## Impact

- **影響ファイル**: `plugins/twl/skills/co-issue/SKILL.md`, `deps.yaml`
- **新規ファイル**: `tests/scenarios/co-issue-v2-smoke.test.sh`
- **前提**: Issue #491 の `scripts/issue-lifecycle-*.sh` と `workflow-issue-lifecycle` SKILL.md が merge 済みであること
- **回帰なし**: flag==0 既存パスは完全維持（co-issue-skill.test.sh が引き続き PASS）
- **scope 外**: `tests/scenarios/spec-review-gate.test.sh`, `docs/issue-mgmt.md` IM-1/2/3, `deltaspec/changes/issue-447/`（#493 cutover スコープ）
