# Component Mapping: claude-plugin-dev → loom-plugin-dev

旧 dev plugin (claude-plugin-dev) の全コンポーネントと新 loom-plugin-dev の対応関係。

カテゴリ:
- **吸収**: 新コンポーネントに統合（名称変更含む）
- **削除**: 新アーキテクチャで不要
- **移植**: ロジック維持でインターフェース適応
- **新規**: 旧にない新コンポーネント

## Controller (旧 9 → 新 4)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| controller-autopilot | 吸収 | co-autopilot | ADR-001: autopilot-first。全 Implementation を統括 |
| controller-self-improve | 吸収 | co-autopilot | ADR-002: 自リポジトリ Issue 検出時に ECC 照合を workflow 内で自動追加 |
| controller-issue | 吸収 | co-issue | ADR-002: 責務変更なし、名称統一 |
| controller-issue-refactor | 削除 | (merge-gate + co-issue) | ADR-002: merge-gate の自動 Issue 起票で代替。手動なら loom audit → co-issue |
| controller-project | 吸収 | co-project | ADR-002: create 引数として統合 |
| controller-project-migrate | 吸収 | co-project | ADR-002: migrate 引数として統合 |
| controller-project-snapshot | 吸収 | co-project | ADR-002: snapshot 引数として統合 |
| controller-plugin | 吸収 | co-project | ADR-002: テンプレート "plugin" として吸収。保守は通常ワークフロー + loom CLI |
| controller-architect | 吸収 | co-architect | ADR-002: 責務変更なし、名称統一 |

## Workflow (旧 5 → 新: 再設計)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| workflow-setup | 移植 | workflow-setup | chain-driven 再構築（B-4）。--auto/--auto-merge フラグ廃止 |
| workflow-test-ready | 移植 | workflow-test-ready | chain-driven 再構築（B-4） |
| workflow-pr-cycle | 移植 | workflow-pr-cycle | chain-driven 再構築（B-5）。merge-gate 統合パス |
| workflow-tech-debt-triage | 移植 | workflow-tech-debt-triage | ロジック維持、C-4 スコープ |
| workflow-dead-cleanup | 移植 | workflow-dead-cleanup | ロジック維持、C-4 スコープ |

## Atomic Skill (旧 4 → 新 4)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| explore | 移植 | explore | C-4: インターフェース適応のみ |
| propose | 移植 | propose | C-4: インターフェース適応のみ |
| apply | 移植 | apply | C-4: インターフェース適応のみ |
| archive | 移植 | archive | C-4: インターフェース適応のみ |

## Composite (旧 7 → 新: 再設計)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| phase-review | 移植 | phase-review | 動的レビュアー構築に変更（B-5）。specialist リストを変更ファイルから決定 |
| merge-gate | 移植 | merge-gate | standard/plugin 2パス廃止 → 統一パス（B-5） |
| issue-assess | 移植 | issue-assess | C-4: インターフェース適応のみ |
| test-scaffold | 移植 | test-scaffold | C-4: インターフェース適応のみ |
| post-fix-verify | 移植 | post-fix-verify | C-4: インターフェース適応のみ |
| plugin-phase-diagnose | 削除 | (co-project 内) | controller-plugin 廃止に伴い統合 |
| plugin-phase-verify | 削除 | (co-project 内) | controller-plugin 廃止に伴い統合 |

## Atomic Command (旧 70 → 新: 再編)

### Project Management

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| project-create | 移植 | project-create | C-4: co-project から呼び出し |
| project-governance | 移植 | project-governance | C-4 |
| setup-crg | 移植 | setup-crg | C-4 |
| container-dependency-check | 移植 | container-dependency-check | C-4 |
| snapshot-analyze | 移植 | snapshot-analyze | C-4: co-project snapshot 内 |
| snapshot-classify | 移植 | snapshot-classify | C-4 |
| snapshot-generate | 移植 | snapshot-generate | C-4 |
| project-migrate | 移植 | project-migrate | C-4: co-project migrate 内 |
| project-board-sync | 移植 | project-board-sync | C-4 |
| project-board-status-update | 移植 | project-board-status-update | C-4 |

### Autopilot

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| autopilot-init | 移植 | autopilot-init | B-3: セッション構造変更。統一状態ファイル対応 |
| autopilot-launch | 移植 | autopilot-launch | B-3: Worker 起動ロジック変更 |
| autopilot-poll | 移植 | autopilot-poll | B-3: マーカーファイル→統一 JSON 監視 |
| autopilot-collect | 移植 | autopilot-collect | C-4: インターフェース適応のみ |
| autopilot-retrospective | 移植 | autopilot-retrospective | C-4 |
| autopilot-patterns | 移植 | autopilot-patterns | C-4 |
| autopilot-cross-issue | 移植 | autopilot-cross-issue | C-4 |
| autopilot-phase-execute | 移植 | autopilot-phase-execute | B-3: Phase 実行ロジック変更 |
| autopilot-phase-postprocess | 移植 | autopilot-phase-postprocess | C-4 |
| autopilot-summary | 移植 | autopilot-summary | C-4 |
| session-audit | 移植 | session-audit | C-4 |

### PR Cycle

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| ac-extract | 移植 | ac-extract | C-4 |
| ac-deploy-trigger | 移植 | ac-deploy-trigger | C-4 |
| ac-verify | 移植 | ac-verify | C-4 |
| scope-judge | 移植 | scope-judge | C-4 |
| test-phase | 移植 | test-phase | C-4 |
| fix-phase | 移植 | fix-phase | C-4 |
| e2e-screening | 移植 | e2e-screening | C-4 |
| warning-fix | 移植 | warning-fix | C-4 |
| pr-cycle-report | 移植 | pr-cycle-report | C-4 |
| pr-cycle-analysis | 移植 | pr-cycle-analysis | C-4 |
| all-pass-check | 移植 | all-pass-check | C-4 |
| auto-merge | 移植 | auto-merge | C-4 |
| spec-diagnose | 移植 | spec-diagnose | C-4 |

### Issue Management

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| issue-structure | 移植 | issue-structure | C-4 |
| issue-dig | 移植 | issue-dig | C-4 |
| issue-tech-debt-absorb | 移植 | issue-tech-debt-absorb | C-4 |
| issue-create | 移植 | issue-create | C-4 |
| issue-bulk-create | 移植 | issue-bulk-create | C-4 |

### Architecture

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| architect-completeness-check | 移植 | architect-completeness-check | C-4 |
| architect-decompose | 移植 | architect-decompose | C-4 |
| architect-group-refine | 移植 | architect-group-refine | C-4 |
| architect-issue-create | 移植 | architect-issue-create | C-4 |
| evaluate-architecture | 移植 | evaluate-architecture | C-4 |

### Setup & Utility

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| init | 移植 | init | C-4: bare repo 検証追加 |
| check | 移植 | check | C-4 |
| worktree-create | 移植 | worktree-create | C-4 |
| worktree-delete | 移植 | worktree-delete | C-4 |
| worktree-list | 移植 | worktree-list | C-4 |
| services | 移植 | services | C-4 |
| ui-capture | 移植 | ui-capture | C-4 |
| e2e-plan | 移植 | e2e-plan | C-4 |
| crg-auto-build | 移植 | crg-auto-build | C-4 |
| schema-update | 移植 | schema-update | C-4 |
| ts-preflight | 移植 | ts-preflight | C-4 |

### Self-improve

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| self-improve-collect | 吸収 | (co-autopilot 内) | ADR-002: self-improve を co-autopilot に統合 |
| self-improve-propose | 吸収 | (co-autopilot 内) | ADR-002 |
| self-improve-close | 吸収 | (co-autopilot 内) | ADR-002 |
| ecc-monitor | 吸収 | (co-autopilot 内) | ADR-002 |

### Plugin Management

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| plugin-interview | 吸収 | (co-project 内) | ADR-002: plugin → co-project テンプレート |
| plugin-research | 吸収 | (co-project 内) | ADR-002 |
| plugin-design | 吸収 | (co-project 内) | ADR-002 |
| plugin-generate | 吸収 | (co-project 内) | ADR-002 |
| plugin-migrate-analyze | 吸収 | (co-project 内) | ADR-002 |
| plugin-diagnose | 削除 | (通常ワークフロー) | ADR-002: 保守は通常ワークフロー + loom CLI |
| plugin-fix | 削除 | (通常ワークフロー) | ADR-002 |
| plugin-verify | 削除 | (通常ワークフロー) | ADR-002 |

### OpenSpec Wrapper

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| opsx-propose | 移植 | opsx-propose | C-4 |
| opsx-apply | 移植 | opsx-apply | C-4 |
| opsx-archive | 移植 | opsx-archive | C-4 |

### Loom Framework

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| loom-validate | 移植 | loom-validate | C-4 |
| dead-component-detect | 移植 | dead-component-detect | C-4 |
| dead-component-execute | 移植 | dead-component-execute | C-4 |
| triage-execute | 移植 | triage-execute | C-4 |

## Specialist (旧 27 → 新: 再編)

### Reviewer (常時)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| worker-code-reviewer | 移植 | worker-code-reviewer | C-4: 出力スキーマ標準化（ADR-004） |
| worker-security-reviewer | 移植 | worker-security-reviewer | C-4: 出力スキーマ標準化 |

### Reviewer (Conditional)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| worker-nextjs-reviewer | 移植 | worker-nextjs-reviewer | C-4: 動的レビュアー構築で条件判定 |
| worker-fastapi-reviewer | 移植 | worker-fastapi-reviewer | C-4 |
| worker-hono-reviewer | 移植 | worker-hono-reviewer | C-4 |
| worker-r-reviewer | 移植 | worker-r-reviewer | C-4 |
| worker-e2e-reviewer | 移植 | worker-e2e-reviewer | C-4 |
| worker-data-validator | 移植 | worker-data-validator | C-4 |
| worker-spec-reviewer | 移植 | worker-spec-reviewer | C-4 |
| worker-env-validator | 移植 | worker-env-validator | C-4 |
| worker-llm-output-reviewer | 移植 | worker-llm-output-reviewer | C-4 |
| worker-llm-eval-runner | 移植 | worker-llm-eval-runner | C-4 |
| worker-supabase-migration-checker | 移植 | worker-supabase-migration-checker | C-4 |
| worker-rls-reviewer | 移植 | worker-rls-reviewer | C-4 |

### Loom Framework Specialist

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| worker-structure | 移植 | worker-structure | C-4: 出力スキーマ標準化 |
| worker-principles | 移植 | worker-principles | C-4 |
| worker-architecture | 移植 | worker-architecture | C-4 |

### Non-reviewer Specialist

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| docs-researcher | 移植 | docs-researcher | C-4 |
| template-validator | 移植 | template-validator | C-4 |
| context-checker | 移植 | context-checker | C-4 |
| pr-test | 移植 | pr-test | C-4 |
| e2e-quality | 移植 | e2e-quality | C-4 |
| autofix-loop | 移植 | autofix-loop | C-4 |
| spec-scaffold-tests | 移植 | spec-scaffold-tests | C-4 |
| e2e-generate | 移植 | e2e-generate | C-4 |
| e2e-heal | 移植 | e2e-heal | C-4 |
| e2e-visual-heal | 移植 | e2e-visual-heal | C-4 |

## Script (旧 17 → 新: 再編)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| autopilot-plan.sh | 移植 | autopilot-plan.sh | B-3: plan.yaml 生成ロジック変更 |
| autopilot-init-session.sh | 移植 | autopilot-init-session.sh | B-3: 統一状態ファイル初期化 |
| autopilot-should-skip.sh | 移植 | autopilot-should-skip.sh | B-3: skip 判定ロジック変更 |
| merge-gate-init.sh | 移植 | merge-gate-init.sh | B-5: 動的レビュアー構築ロジック |
| merge-gate-execute.sh | 移植 | merge-gate-execute.sh | B-5: 統一パス判定ロジック |
| merge-gate-issues.sh | 移植 | merge-gate-issues.sh | B-5 |
| parse-issue-ac.sh | 移植 | parse-issue-ac.sh | C-4 |
| classify-failure.sh | 移植 | classify-failure.sh | C-4 |
| create-harness-issue.sh | 移植 | create-harness-issue.sh | C-4 |
| codex-review.sh | 移植 | codex-review.sh | C-4 | ※ #22 で削除済み |
| project-create.sh | 移植 | project-create.sh | C-4 |
| project-migrate.sh | 移植 | project-migrate.sh | C-4 |
| worktree-create.sh | 移植 | worktree-create.sh | C-4 |
| worktree-delete.sh | 移植 | worktree-delete.sh | C-4 |
| session-audit.sh | 移植 | session-audit.sh | C-4 |
| check-db-migration.py | 移植 | check-db-migration.py | C-4 |
| ecc-monitor.sh | 吸収 | (co-autopilot 内) | ADR-002: self-improve 統合 |

## Reference (旧 11 → 新: 再編)

| 旧コンポーネント | カテゴリ | 新コンポーネント | 根拠 |
|---|---|---|---|
| baseline-coding-style | 移植 | baseline-coding-style | C-4 |
| baseline-security-checklist | 移植 | baseline-security-checklist | C-4 |
| baseline-input-validation | 移植 | baseline-input-validation | C-4 |
| self-improve-format | 吸収 | (co-autopilot 内) | ADR-002: self-improve 統合 |
| ref-types | 移植 | ref-types | C-4 |
| ref-deps-format | 移植 | ref-deps-format | C-4 |
| ref-practices | 移植 | ref-practices | C-4 |
| ref-architecture | 移植 | ref-architecture | C-4 |
| ref-architecture-spec | 移植 | ref-architecture-spec | C-4 |
| ref-project-model | 移植 | ref-project-model | C-4 |
| ref-dci | 移植 | ref-dci | C-4 |

## 新規コンポーネント

| コンポーネント | 種別 | 根拠 |
|---|---|---|
| tech-stack-detect (script) | script | Issue #3 設計判断 #7: 動的レビュアー構築用 tech-stack 検出 |
| state-read.sh / state-write.sh (script) | script | ADR-003: 統一状態ファイル JSON read/write ヘルパー |
| self-improve-review (atomic) | atomic | ADR-005: エラーサマリー提示 → co-issue Phase 2 接続 |

## サマリー

| 種別 | 旧 | 吸収 | 削除 | 移植 | 新規 |
|------|-----|------|------|------|------|
| Controller | 9 | 9 | 0 | 0 | 0 |
| Workflow | 5 | 0 | 0 | 5 | 0 |
| Atomic Skill | 4 | 0 | 0 | 4 | 0 |
| Composite | 7 | 0 | 2 | 5 | 0 |
| Atomic Command | 70 | 8 | 3 | 59 | 1 |
| Specialist | 27 | 0 | 0 | 27 | 0 |
| Script | 17 | 1 | 0 | 16 | 2 |
| Reference | 11 | 1 | 0 | 10 | 0 |
| **合計** | **150** | **19** | **5** | **126** | **3** |
