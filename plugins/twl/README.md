# plugin-twl

Claude Code twl plugin（chain-driven + autopilot-first）。claude-plugin-dev の後継として新規構築。

## 設計哲学

**LLM は判断のために使う。機械的にできることは機械に任せる。**

- **Chain-driven**: ワークフローは chain（step の連鎖）として定義。各 step は atomic command として独立実行可能
- **Autopilot-first**: 単一 Issue も co-autopilot 経由で実装。手動介入を最小化

## Entry Points

<!-- ENTRY-POINTS-START -->
### Controllers

| Controller | 説明 |
|---|---|
| co-autopilot | 依存グラフに基づくIssue群一括自律実装オーケストレーター |
| co-issue | 要望をGitHub Issueに変換するワークフロー（thin orchestrator）。refine フェーズは workflow-issue-refine に完全委譲（ADR-0010）。explore-summary 入力必須。DAG 依存解決 + level dispatch + aggregate |
| co-explore | 問題探索の独立コントローラー。explore-summary を .explore/<N>/summary.md に保存し Issue リンクで co-issue / co-architect に接続 |
| co-project | プロジェクト管理（create / migrate / snapshot / plugin-create / plugin-diagnose / prompt-audit） |
| co-architect | 対話的アーキテクチャ構築ワークフロー（explore-summary 入力、branch/PR + review フロー付き） |
| co-utility | standalone ユーティリティコマンドの統合エントリポイント |
| co-self-improve | ライブセッション観察と能動的 self-improvement framework のエントリポイント controller |

### Supervisors

| Supervisor | 説明 |
|---|---|
| su-observer | メタ認知レイヤー: 全 controller の監視・介入。hook プライマリ / polling フォールバックの Hybrid 検知（#570）。テストシナリオ実行は co-self-improve に委譲 |
<!-- ENTRY-POINTS-END -->

## Components

| カテゴリ | 数 | 内訳 |
|---|---|---|
| Skills | 12 | controller 5 + workflow 7 |
| Commands | 92 | atomic 83 + composite 9 |
| Agents | 29 | specialist 29 |
| Refs | 23 | reference 23（ref-invariants 含む、#984: su-observer-supervise-channels / su-observer-controller-spawn-playbook / su-observer-wave-management / su-observer-security-gate 追加） |
| Scripts | 28 | script 28 |
| **合計** | **184** | |

## 使い方

Issue 起点の開発フロー:

```bash
# 1. 開発準備（worktree 作成）
/twl:workflow-setup #<issue-number>

# 2. 実装・テスト（TDD サイクル）
/twl:workflow-test-ready

# 3. PR 検証
/twl:workflow-pr-verify

# 4. PR マージ
/twl:workflow-pr-merge
```

Autopilot で複数 Issue を一括実装:

```bash
/twl:co-autopilot
```

## Architecture

Notable scripts: `specialist-audit` (specialist completeness 監査 — merge-gate および su-observer から呼び出し、JSONL の specialist 実行数を期待集合と照合し JSON 形式で結果を出力)

<!-- DEPS-GRAPH-START -->
| From | To |
|------|-----|
| twl:co-autopilot | autopilot-init, autopilot-launch, autopilot-poll, autopilot-phase-execute, autopilot-pilot-wakeup-bootstrap, autopilot-pilot-wakeup-poll, autopilot-pilot-wakeup-heartbeat, autopilot-phase-sanity, autopilot-pilot-precheck, autopilot-pilot-rebase, autopilot-multi-source-verdict, autopilot-phase-postprocess, autopilot-collect, autopilot-retrospective, autopilot-patterns, autopilot-cross-issue, autopilot-summary, session-audit, self-improve-review, →twl:workflow-setup, →twl:workflow-test-ready, →twl:workflow-pr-verify, →twl:workflow-pr-fix, →twl:workflow-pr-merge, →twl:workflow-dead-cleanup, →twl:workflow-tech-debt-triage, →twl:workflow-self-improve, →twl:co-autopilot-emergency-bypass |
| twl:co-issue | issue-glossary-check, →twl:workflow-issue-lifecycle, →twl:workflow-issue-refine, →twl:co-issue-step0.5-modes, →twl:co-issue-phase2-bundles, →twl:co-issue-phase3-dispatch, →twl:co-issue-phase4-aggregate, →twl:co-issue-cleanup |
| twl:co-project | project-create, project-governance, project-board-configure, project-migrate, container-dependency-check, setup-crg, snapshot-analyze, snapshot-classify, snapshot-generate, →twl:workflow-plugin-create, →twl:workflow-plugin-diagnose, →twl:workflow-prompt-audit, label-sync, →twl:ref-types, →twl:ref-practices, →twl:ref-deps-format |
| twl:co-architect | architect-completeness-check, architect-group-refine, evaluate-architecture, →twl:ref-architecture-spec, →twl:ref-skill-arch-patterns, →twl:workflow-arch-review |
| twl:co-utility | worktree-list, worktree-delete, twl-validate, services, ui-capture, schema-update |
| twl:co-self-improve | →twl:workflow-observe-loop, test-project-init, test-project-reset, test-project-scenario-load, observe-once, problem-detect, issue-draft-from-observation, observe-retrospective, ●observer-evaluator, →twl:test-scenario-catalog, →twl:observation-pattern-catalog, →twl:load-test-baselines |
| twl:su-observer | observe-once, problem-detect, ●observer-evaluator, intervene-auto, intervene-confirm, intervene-escalate, →twl:intervention-catalog, →twl:observation-pattern-catalog, →twl:monitor-channel-catalog, su-compact, wave-collect, externalize-state, →twl:pitfalls-catalog, →twl:proxy-dialog-playbook, →twl:ref-invariants, →twl:observer-supervise-checklist, →twl:su-observer-supervise-channels, →twl:su-observer-controller-spawn-playbook, →twl:su-observer-wave-management, →twl:su-observer-security-gate, →twl:su-observer-constraints |
| twl:workflow-setup | init, worktree-create, project-board-status-update, crg-auto-build, ac-extract |
| twl:workflow-test-ready | ◆test-scaffold, check, e2e-plan |
| twl:workflow-pr-verify | ac-deploy-trigger, prompt-compliance, ts-preflight, ◆phase-review, scope-judge, pr-test, ac-verify, ◆test-phase |
| twl:workflow-pr-fix | ◆fix-phase, ◆post-fix-verify, warning-fix |
| twl:workflow-pr-merge | ◆e2e-screening, pr-cycle-report, pr-cycle-analysis, all-pass-check, ◆merge-gate, auto-merge, →twl:pr-merge-domain-rules, →twl:pr-merge-chain-steps |
| twl:workflow-dead-cleanup | dead-component-detect, dead-component-execute |
| twl:workflow-tech-debt-triage | triage-execute |
| twl:workflow-self-improve | self-improve-collect, self-improve-propose, self-improve-close, ecc-monitor |
| twl:workflow-observe-loop | ◆observe-and-detect, observe-retrospective |
| twl:workflow-plugin-create | plugin-interview, plugin-research, plugin-design, plugin-generate |
| twl:workflow-plugin-diagnose | plugin-migrate-analyze, plugin-diagnose, ◆plugin-phase-diagnose, plugin-fix, plugin-verify, ◆plugin-phase-verify |
| twl:workflow-prompt-audit | prompt-audit-scan, ◆prompt-audit-review, prompt-audit-apply |
| twl:workflow-issue-lifecycle | issue-structure, ◆issue-spec-review, issue-review-aggregate, issue-arch-drift, issue-create, project-board-sync, →twl:lifecycle-processing-flow |
| twl:workflow-issue-refine | ◆issue-spec-review, issue-review-aggregate, issue-arch-drift, →twl:refine-processing-flow |
| twl:workflow-arch-review | ◆arch-phase-review, arch-fix-phase, ◆merge-gate, auto-merge |
| post-fix-verify | ●worker-code-reviewer, ●worker-security-reviewer, ●worker-codex-reviewer |
| all-pass-check | →twl:ref-dci |
| issue-spec-review | ●issue-critic, ●issue-feasibility, ●worker-codex-reviewer |
| issue-glossary-check | →twl:ref-glossary-criteria |
| plugin-phase-diagnose | ●worker-structure, ●worker-principles, ●worker-architecture, →twl:ref-specialist-output-schema, →twl:ref-skill-arch-patterns |
| plugin-phase-verify | ●worker-structure, ●worker-principles, ●worker-architecture, →twl:ref-specialist-output-schema, →twl:ref-skill-arch-patterns |
| problem-detect | →twl:observation-pattern-catalog |
| observe-and-detect | ●observer-evaluator |
| su-compact | →twl:memory-mcp-config |
| externalize-state | →twl:externalization-schema |
| intervene-auto | →twl:intervention-catalog |
| intervene-confirm | →twl:intervention-catalog |
| intervene-escalate | →twl:intervention-catalog |
| test-scaffold | ●e2e-generate, →twl:ref-specialist-output-schema |
| phase-review | ●worker-structure, ●worker-principles, ●worker-code-reviewer, ●worker-security-reviewer, ●worker-supabase-migration-checker, ●worker-e2e-reviewer, ●worker-rls-reviewer, ●worker-llm-output-reviewer, ●worker-llm-eval-runner, ●worker-data-validator, ●worker-env-validator, ●worker-codex-reviewer, ●worker-issue-pr-alignment, →twl:ref-specialist-output-schema, →twl:baseline-coding-style, →twl:baseline-security-checklist, →twl:baseline-input-validation, →twl:baseline-bash |
| arch-phase-review | ●worker-arch-doc-reviewer, ●worker-architecture, ●worker-structure, ●worker-principles, →twl:ref-specialist-output-schema |
| merge-gate | ●worker-structure, ●worker-principles, ●worker-code-reviewer, ●worker-security-reviewer, ●worker-supabase-migration-checker, ●worker-e2e-reviewer, ●worker-rls-reviewer, ●worker-llm-output-reviewer, ●worker-llm-eval-runner, ●worker-data-validator, ●worker-env-validator, ●worker-codex-reviewer, ●worker-architecture, ●worker-issue-pr-alignment, →twl:ref-specialist-output-schema, →twl:ref-dci, →twl:baseline-coding-style, →twl:baseline-security-checklist, →twl:baseline-input-validation, →twl:baseline-bash |
| test-phase | ●e2e-quality, →twl:ref-specialist-output-schema |
| autopilot-phase-execute | →twl:ref-dci |
| ⟶worker-structure | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-principles | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-env-validator | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-rls-reviewer | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-supabase-migration-checker | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-data-validator | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶template-validator | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶context-checker | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-e2e-reviewer | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶issue-critic | →twl:ref-issue-quality-criteria, →twl:ref-investigation-budget, →twl:ref-specialist-few-shot |
| ⟶issue-feasibility | →twl:ref-issue-quality-criteria, →twl:ref-investigation-budget, →twl:ref-specialist-few-shot |
| ⟶worker-codex-reviewer | →twl:ref-issue-quality-criteria, →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-code-reviewer | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-security-reviewer | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-arch-doc-reviewer | →twl:ref-specialist-output-schema |
| ⟶worker-architecture | →twl:ref-specialist-output-schema, →twl:ref-skill-arch-patterns, →twl:ref-specialist-few-shot |
| ⟶worker-issue-pr-alignment | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-workflow-integrity | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot, →twl:ref-prompt-guide |
| ⟶worker-llm-output-reviewer | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-llm-eval-runner | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶worker-prompt-reviewer | →twl:ref-prompt-guide, →twl:ref-specialist-output-schema |
| ⟶docs-researcher | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶e2e-quality | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶autofix-loop | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶e2e-generate | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶e2e-heal | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
| ⟶e2e-visual-heal | →twl:ref-specialist-output-schema, →twl:ref-specialist-few-shot |
<!-- DEPS-GRAPH-END -->

<!-- DEPS-SUBGRAPHS-START -->
<!-- DEPS-SUBGRAPHS-END -->
