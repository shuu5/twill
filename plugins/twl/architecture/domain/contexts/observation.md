# Live Observation

## Responsibility

ライブセッション観察、問題検出、Issue 起票、テストプロジェクト管理。
co-self-improve が統括する独立 Bounded Context。既存 Self-Improve Context（受動的 retrospective）とは別レイヤー（ADR-011）。

## Key Entities

### ObservationSession
observer session の状態。

| フィールド | 型 | 説明 |
|---|---|---|
| session_id | string | 観察セッション一意識別子 |
| observed_targets | ObservedTarget[] | 観察対象のリスト |
| status | `observing` \| `paused` \| `completed` | セッション状態 |
| started_at | string (ISO 8601) | 開始時刻 |
| detections | Detection[] | 検出された問題のリスト |

### ObservedTarget
observed session の参照。

| フィールド | 型 | 説明 |
|---|---|---|
| window | string | tmux ウィンドウ名 |
| issue | number \| null | 対応する Issue 番号 |
| project | string | 対象プロジェクト名 |
| type | `autopilot` \| `manual` \| `test-project` | 対象セッションの種別 |

### Detection
検出された問題の単位。

| フィールド | 型 | 説明 |
|---|---|---|
| id | string | 検出一意識別子 |
| severity | `critical` \| `warning` \| `info` | 深刻度 |
| category | string | 問題カテゴリ（例: chain_stall, test_failure, pattern_match） |
| source | `rule-based` \| `llm-evaluated` | 検出手段 |
| capture_excerpt | string | 問題を示す出力の抜粋 |
| timestamp | string (ISO 8601) | 検出時刻 |

### TestProject
隔離 worktree の参照。

| フィールド | 型 | 説明 |
|---|---|---|
| branch | string | test-target ブランチ名 |
| scenario | string | ロードされたシナリオ名 |
| state | `initialized` \| `running` \| `completed` \| `failed` | プロジェクト状態 |
| worktree_path | string | worktree のパス |

### LoadScenario
負荷シナリオの定義。

| フィールド | 型 | 説明 |
|---|---|---|
| name | string | シナリオ名 |
| level | `smoke` \| `regression` \| `load` | テストレベル |
| issue_count | number | 投入する Issue 数 |
| expected_duration | string | 期待完了時間 |

## Key Workflows

### Observe ループ

```mermaid
flowchart TD
    A[co-self-improve 起動] --> B[ObservationSession 作成]
    B --> C[observed target 選択]
    C --> D[capture: tmux 出力取得]
    D --> E[problem-detect: rule-based 検出]
    E --> F{パターンマッチ?}
    F -- Yes --> G[Detection 記録]
    F -- No --> H[observer-evaluator: LLM 判定]
    H --> I{問題検出?}
    I -- Yes --> G
    I -- No --> J{観察継続?}
    G --> K[Issue draft 作成]
    K --> L[ユーザー確認]
    L --> J
    J -- Yes --> D
    J -- No --> M[ObservationSession 完了]
```

### テストプロジェクト管理フロー

```mermaid
flowchart TD
    A[test-project-init: 隔離 worktree 作成] --> B[scenario-load: Issue 群投入]
    B --> C[autopilot 実行]
    C --> D[observe ループ並行]
    D --> E[test-project-reset: クリーンアップ]
```

### Retrospective 抽出フロー

```mermaid
flowchart TD
    A[ObservationSession 完了] --> B[Detection 集約]
    B --> C[パターン抽出]
    C --> D[Observation Pattern 更新]
    D --> E[Self-Improve Context へ連携]
```

## Constraints

- observed session を**書き換えない**（read-only MUST）。observer は tmux capture-pane 等で出力を取得するのみ
- test target は実 twill main の git 履歴を**絶対に汚染しない**。隔離 worktree + 独立ブランチで管理
- observation Issue は本物の Issue とラベルで明確に区別する（`label: from-observation`）

## Rules

- 問題検出は rule-based（problem-detect atomic）を first-pass、specialist（observer-evaluator）を second-pass で実行する
- Issue draft はユーザー確認 MUST。自動起票禁止
- 並列 observe 上限: 同時 3 observed session まで
- **Self-Improve Context との関係**: workflow-self-improve は autopilot 後処理として動く受動側、co-self-improve はユーザートリガーで動く能動側。両者は ADR-011 で並存が明示されている

## Component Mapping

| 種別 | コンポーネント | 役割 |
|------|--------------|------|
| **controller** | co-self-improve | Live Observation 統括。テストプロジェクト管理も担う |
| **workflow** | workflow-observe | observe ループ + 問題検出 + Issue draft |
| **workflow** | workflow-test-project | テストプロジェクト init → scenario-load → 実行 → reset |
| **atomic** | test-project-init | 隔離 worktree 作成 |
| **atomic** | test-project-reset | テストプロジェクト クリーンアップ |
| **atomic** | scenario-load | Issue 群のテストプロジェクトへの投入 |
| **atomic** | problem-detect | rule-based で capture から既知パターンを検出 |
| **specialist** | observer-evaluator | LLM 判定で微妙な問題を検出 |
| **reference** | load-test baseline | 負荷テスト level (smoke/regression/load) の定量基準 |

## Dependencies

- **Upstream <- Issue Management**: observation Issue の起票
- **Upstream <- Project Management**: テストプロジェクト worktree 管理
- **Downstream -> session plugin**: session:observe / session-state.sh でセッション出力を取得
- **並存 -> Self-Improve**: 異なるレイヤー（受動 retrospective と能動 observation の補完関係）
