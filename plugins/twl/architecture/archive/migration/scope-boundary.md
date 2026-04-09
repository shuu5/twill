# Scope Boundary

スコープ分類: セッション構造変更、merge-gate 判定変更、インターフェース適応。

Issue #3 設計判断 #12 に基づくスコープ分類。

## 分類基準

| スコープ | 定義 | 該当 Issue |
|----------|------|-----------|
| **B-3** | セッション構造が変わるコンポーネント。autopilot の状態管理・Phase 実行・計画生成に影響 | #5 |
| **B-5** | merge-gate 判定ロジックが変わるコンポーネント。レビュアー構築・判定基準に影響 | #7 |
| **C-4** | ロジック維持でインターフェースのみ適応するコンポーネント。chain-driven 統合・出力スキーマ適用 | #11 |

## Script 分類

| Script | スコープ | 根拠 |
|--------|---------|------|
| autopilot-plan.sh | B-3 | plan.yaml 生成ロジック（Phase 分割・依存解析）を変更 |
| autopilot-init-session.sh | B-3 | session.json 初期化。マーカーファイル → 統一状態ファイル |
| autopilot-should-skip.sh | B-3 | skip 判定を issue-{N}.json ベースに変更 |
| merge-gate-init.sh | B-5 | 動的レビュアー構築ロジック（変更ファイル → specialist リスト決定） |
| merge-gate-execute.sh | B-5 | 統一パス判定（standard/plugin 2パス → 単一パス） |
| merge-gate-issues.sh | B-5 | REJECT 時の Issue 起票ロジック変更 |
| parse-issue-ac.sh | C-4 | ロジック変更なし、chain step として呼び出し方のみ変更 |
| classify-failure.sh | C-4 | ロジック変更なし |
| create-harness-issue.sh | C-4 | ロジック変更なし |
| codex-review.sh | C-4 | ロジック変更なし | ※ #22 で削除済み |
| project-create.sh | C-4 | bare repo 構造は変更なし（既に対応済み） |
| project-migrate.sh | C-4 | ロジック変更なし |
| worktree-create.sh | C-4 | ロジック変更なし |
| worktree-delete.sh | C-4 | ロジック変更なし |
| session-audit.sh | C-4 | ロジック変更なし |
| check-db-migration.py | C-4 | ロジック変更なし |
| ecc-monitor.sh | B-3 | co-autopilot 内に吸収（self-improve 統合） |

## Atomic Command 分類

### B-3 スコープ（セッション構造変更）

| コンポーネント | 根拠 |
|---|---|
| autopilot-init | 統一状態ファイル（session.json + issue-{N}.json）初期化 |
| autopilot-launch | Worker 起動ロジック（CWD=main/ → tmux new-window） |
| autopilot-poll | マーカーファイル → issue-{N}.json 監視に変更 |
| autopilot-phase-execute | Phase 実行ループの状態管理を統一 JSON に変更 |

### B-5 スコープ（merge-gate 判定ロジック変更）

| コンポーネント | 根拠 |
|---|---|
| merge-gate (composite) | 動的レビュアー構築 + 統一パス判定 |
| phase-review (composite) | 動的レビュアー構築連動 |

### C-4 スコープ（インターフェース適応のみ）

上記以外の全 Atomic Command、Specialist、Reference は C-4 スコープ。
chain-driven 統合（deps.yaml chains 定義）と出力スキーマ標準化（ADR-004）への適応のみ。

## Workflow 分類

| Workflow | スコープ | 根拠 |
|----------|---------|------|
| workflow-setup | B-3 + B-4 | chain-driven 再構築。--auto/--auto-merge 廃止 |
| workflow-test-ready | B-4 | chain-driven 再構築 |
| workflow-pr-cycle | B-5 | merge-gate 統合パス対応 |
| workflow-tech-debt-triage | C-4 | ロジック変更なし |
| workflow-dead-cleanup | C-4 | ロジック変更なし |
