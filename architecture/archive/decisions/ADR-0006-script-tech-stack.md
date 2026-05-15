# ADR-0006: scripts 技術スタック選択基準（Python/bash 分類）

## Status

Accepted

## Context

`plugins/twl/scripts/` には 35 本のスクリプト（bash 34 本 + Python 1 本、計 7,133 行）が存在する。
その多くが bash に不向きな処理を実装している:

- **JSON 状態管理**: `jq` を 150 回以上使用（`state-write.sh`, `chain-runner.sh` 等）
- **ステートマシン**: `chain-runner.sh`（16 ステップの遷移・リカバリ）
- **ポーリングループ**: `autopilot-orchestrator.sh`（最大 360 回ループ）
- **GraphQL レスポンス処理**: `project-create.sh`, `autopilot-plan.sh` 等
- **YAML 解析**: `autopilot-plan.sh`

一方 TWiLL CLI はすでに Python（`cli/twl/` の `src/twl/` パッケージ）として実装されており、
`scripts/check-db-migration.py` は bash→Python 移管の先行事例となっている。

リポジトリ全体でスクリプトの技術スタック選択基準が明文化されておらず、
後続の Python 移管 Issue の判断根拠として ADR を作成する。

## Decision

### 選択基準

| 処理の主体 | 採用言語 | 根拠 |
|---|---|---|
| **データ構造操作** | Python | JSON/YAML 読み書き、状態遷移、GraphQL レスポンス処理、ポーリング・並列管理 |
| **プロセス操作** | bash | tmux pane 制御、git CLI ラッパー、Claude Code hook イベント処理 |

### 詳細定義

**Python 化すべき処理**:
- JSON の読み書き・変換・バリデーション（`jq` で代替している処理を含む）
- 状態遷移ロジック（ステートマシン、遷移バリデーション）
- ポーリングループや並列プロセス管理
- GitHub GraphQL API レスポンスの構造的処理
- YAML パースと意味的な変換

**bash に留める処理**:
- `tmux new-window`, `tmux send-keys` 等のウィンドウ・ペイン制御
- `git worktree add/remove` 等の git サブコマンド直呼び出し
- Claude Code hook（`PreToolUse`, `PostToolUse`, `PostCompact` 等）のイベント受け取りと即時 stdout 注入
- 短い glue スクリプト（入力を受け取り他スクリプトに渡すだけのもの、概ね 50 行以下）

### 境界ケースの判定ルール

「JSON 加工」と「外部プロセス呼び出し」が混在するスクリプトは、**主要処理の比率**で判定する:

| 例 | 判定 | 理由 |
|---|---|---|
| jq でのフィールド抽出 + `gh pr create` | bash 可 | gh CLI の引数生成が主目的。JSON は補助的 |
| JSON 状態読み取り → 遷移バリデーション → JSON 書き込み | Python | データ構造操作が主目的。プロセス呼び出しは副次 |
| `tmux send-keys` + `jq` で出力整形 | bash | tmux 操作が主目的 |
| ポーリングループ + JSON 状態更新（360 回） | Python | ループ管理とデータ更新が主目的 |

50 行超で `jq` が 3 回以上登場する場合は Python 化を検討する目安とする。

### deps.yaml の script 型における `.py` パス対応

deps.yaml v3.0 の `script` 型は `.py` ファイルパスを直接サポートしている。
`.sh` と同じ記法で宣言可能:

```yaml
scripts:
  check-db-migration:
    type: script
    path: scripts/check-db-migration.py   # .py パス — .sh と同じ記法
    description: "DB マイグレーション整合性チェック（Python）"
```

既存の先行実装として `scripts/check-db-migration.py`（328 行）が deps.yaml に登録済み。

### 全スクリプト分類表

#### Python 化すべきスクリプト（データ構造操作が主）

| スクリプト | 行数 | 主な処理 | 判定理由 | 移行優先度 |
|---|---|---|---|---|
| `chain-runner.sh` | 704 | 16 ステップのステートマシン + JSON 状態管理 | 状態遷移ロジックが主体。`jq` 15 回 | 高 |
| `state-write.sh` | 278 | JSON 書き込み + 遷移バリデーション | 全処理がデータ構造操作。`jq` 13 回 | 高 |
| `state-read.sh` | 109 | JSON 読み取り + フィールド抽出 | 全処理がデータ構造操作。`jq` 6 回 | 高 |
| `autopilot-orchestrator.sh` | 946 | 360 回ポーリング + 並列管理 + JSON 状態更新 | ループ管理とデータ更新が主体 | 高 |
| `autopilot-plan.sh` | 603 | YAML 解析 + GraphQL レスポンス処理 + plan.yaml 生成 | YAML/JSON 操作が主体。`jq` 6 回 | 高 |
| `autopilot-plan-board.sh` | 150 | GraphQL で Project Board 情報取得・整形 | GraphQL レスポンス処理が主体。`jq` 5 回 | 高 |
| `parse-issue-ac.sh` | 120 | Issue body から AC 抽出（テキスト構造解析） | テキスト構造のパースが主体。`jq` 5 回 | 中 |
| `session-audit.sh` | 208 | JSONL 解析 + 5 カテゴリ検出 + 統計集計 | 全処理がデータ解析。`jq` 17 回 | 中 |
| `project-create.sh` | 484 | GraphQL で Project 作成 + フィールド設定 | GraphQL 操作が主体。`jq` 7 回 | 中 |
| `project-board-backfill.sh` | 150 | GraphQL でアイテム取得 + ステータス更新 | GraphQL + JSON 操作が主体。`jq` 6 回 | 中 |
| `project-board-archive.sh` | 85 | GraphQL でアーカイブ済み取得 + JSON 整形 | GraphQL + JSON 操作が主体。`jq` 6 回 | 中 |
| `merge-gate-execute.sh` | 180 | JSON 状態読み取り + 条件分岐 + 状態書き込み | 状態管理ロジックが主体。`jq` 6 回 | 中 |
| `ecc-monitor.sh` | 135 | ECC エラーログ解析 + JSON 集計 | データ解析が主体。`jq` 5 回 | 低 |
| `health-report.sh` | 131 | JSON 状態読み取り + レポート生成 | データ集計・整形が主体 | 低 |
| `specialist-output-parse.sh` | 73 | specialist 出力の JSON スキーマパース | JSON パースが主体。`jq` 4 回 | 低 |
| `checkpoint-write.sh` | 100 | チェックポイント JSON 書き込み | データ書き込みが主体 | 低 |
| `checkpoint-read.sh` | 76 | チェックポイント JSON 読み取り | データ読み取りが主体 | 低 |
| `autopilot-init.sh` | 165 | `.autopilot/` 初期化 + 排他制御 + JSON 生成 | JSON 生成とファイル管理が主体。`jq` 8 回 | 低 |
| `session-create.sh` | 85 | session.json 新規作成（JSON 生成） | JSON 生成が主体 | 低 |
| `project-migrate.sh` | 281 | Project アーカイブ + 新規作成 + 移行 | GraphQL + JSON 操作が主体 | 低 |
| `compaction-resume.sh` | 130 | JSON 状態読み取り + ステップ完了判定 | JSON 読み取りと論理判定が主体 | 低 |

#### bash に留めるスクリプト（プロセス操作が主）

| スクリプト | 行数 | 主な処理 | 判定理由 |
|---|---|---|---|
| `autopilot-launch.sh` | 302 | tmux window 作成 + `cld` 起動 + フック設定 | tmux・プロセス操作が主体 |
| `worktree-create.sh` | 237 | `git worktree add` + ブランチ作成 | git CLI ラッパーが主体 |
| `worktree-delete.sh` | 103 | `git worktree remove` + ブランチ削除 | git CLI ラッパーが主体 |
| `auto-merge.sh` | 211 | `gh pr merge` + CI チェック待機 | gh CLI 操作が主体 |
| `crash-detect.sh` | 144 | tmux pane 状態確認 + session-state.sh 呼び出し | プロセス状態監視が主体 |
| `health-check.sh` | 254 | tmux pane 出力解析 + 論理的異常検知 | プロセス監視が主体（tmux 密結合） |
| `session-archive.sh` | 64 | セッションファイルのアーカイブ（mv/cp） | ファイル操作が主体 |
| `session-add-warning.sh` | 66 | session.json への警告追記（JSON append） | 境界ケース: 50 行超だが処理が単純な append のみ |
| `tech-stack-detect.sh` | 76 | ファイルパス・拡張子から tech-stack 判定 | 入力→パターンマッチ→出力の glue スクリプト |
| `resolve-issue-num.sh` | 63 | ブランチ名から Issue 番号抽出 | 短い glue スクリプト（正規表現抽出のみ） |
| `escape-issue-body.sh` | 7 | Issue body の特殊文字エスケープ | 短い glue スクリプト（7 行） |
| `chain-steps.sh` | 38 | chain ステップ順序定義（配列） | 設定ファイル的役割。Python 化で得るものが少ない |
| `autopilot-should-skip.sh` | 47 | 依存グラフ skip 判定 | 短い glue スクリプト |

#### hooks/ 配下（Claude Code hook イベント専用）

| スクリプト | 行数 | 判定 |
|---|---|---|
| `hooks/permission-request-auto-approve.sh` | — | bash 維持（hook stdout 注入が必須） |
| `hooks/post-compact-checkpoint.sh` | — | bash 維持（hook stdout 注入が必須） |
| `hooks/post-tool-use-bash-error.sh` | — | bash 維持（hook stdout 注入が必須） |
| `hooks/post-tool-use-validate.sh` | — | bash 維持（hook stdout 注入が必須） |
| `hooks/pre-compact-checkpoint.sh` | — | bash 維持（hook stdout 注入が必須） |
| `hooks/pre-tool-use-ask-user-question.sh` | — | bash 維持（hook stdout 注入が必須） |

hooks/ は Claude Code が直接呼び出し stdout を読む。Python 化した場合も bash ラッパー必須であり移管メリットがない。

#### lib/ 配下

| スクリプト | 行数 | 判定 |
|---|---|---|
| `lib/resolve-project.sh` | — | bash 維持（chain-runner.sh に source される glue） |

#### 既存 Python スクリプト

| スクリプト | 行数 | 備考 |
|---|---|---|
| `check-db-migration.py` | 328 | DB マイグレーション整合性チェック。bash→Python 移管の先行事例 |

## Consequences

### Positive

- 後続の Python 移管 Issue（状態管理・オーケストレーション・merge-gate・プロジェクト管理）の判断基準が明確になる
- `jq` の複雑な pipe chain を Python の辞書操作で置き換え、テスト容易性が向上する
- ステートマシンとポーリングループを Python のクラスで実装することでバグの検出が容易になる

### Negative

- 移管中は bash/Python の混在期間が生じる。呼び出し側（chain-runner.sh 等）は移管完了まで bash のまま残る
- Python スクリプトには `#!/usr/bin/env python3` と deps.yaml への登録が必要。bash より起動コストがわずかに増加する

### Neutral

- `plugins/session/scripts/` は tmux 密結合のため本 ADR のスコープ外。bash 維持とする
- 移管の実施タイミングは各後続 Issue で個別に決定する

## Subsequent Issues

本 ADR が前提条件（blocks）となる後続 Issue 群:

| Issue | 対象スクリプト | 内容 |
|---|---|---|
| 状態管理 Python 化 | `state-read.sh`, `state-write.sh`, `compaction-resume.sh`, `checkpoint-read/write.sh` | JSON 状態 I/O の Python モジュール化 |
| オーケストレーション Python 化 | `autopilot-orchestrator.sh`, `autopilot-plan.sh`, `autopilot-plan-board.sh` | ポーリングループ・並列管理・YAML 処理の Python 化 |
| merge-gate Python 化 | `merge-gate-execute.sh` | 状態読み取り + 条件分岐の Python 化 |
| プロジェクト管理 Python 化 | `project-create.sh`, `project-migrate.sh`, `project-board-*.sh` | GraphQL 操作の Python 化 |
| chain-runner Python 化 | `chain-runner.sh` | ステートマシンの Python 化（最終ステップ。上記が前提） |

依存方向: 本 ADR → 状態管理 → chain-runner（最後）
