# Self-Improve

## Responsibility

開発セッション中のパターン検出、ECC (External Context Cache) との照合、改善 Issue の起票。
co-autopilot に吸収されており、独立 controller は存在しない。

## Key Entities

### Pattern
検出されたパターン。merge-gate findings やセッション失敗から抽出される。

| フィールド | 型 | 説明 |
|---|---|---|
| name | string | パターン名 |
| count | number | 検出回数 |
| last_seen | string (ISO 8601) | 最後に検出された時刻 |
| source | `merge-gate findings` \| `session failures` | 検出元 |

### ECCReference
外部知識ソース。doobidoo memory に保存された過去の知見。

| フィールド | 型 | 説明 |
|---|---|---|
| hash | string | memory のハッシュ |
| content | string | 知見の内容 |
| quality | number | 品質スコア |

### SelfImproveIssue
通常 Issue + self-improve-format テンプレートで構造化された改善 Issue。

| フィールド | 型 | 説明 |
|---|---|---|
| detection_source | string | 検出元の情報 |
| confidence | `HIGH` \| `MEDIUM` \| `LOW` | 改善の確信度 |
| pattern_name | string | 対応する Pattern 名 |

### ErrorRecord
hook が自動記録する Bash エラー。

| フィールド | 型 | 説明 |
|---|---|---|
| timestamp | string (ISO 8601) | エラー発生時刻 |
| command | string | 実行されたコマンド |
| exit_code | number | 終了コード |
| stderr_snippet | string | stderr の先頭部分 |
| cwd | string | 実行時の作業ディレクトリ |

## Key Workflows

### パターン検出フロー

```mermaid
flowchart TD
    A[autopilot Phase 完了] --> B[autopilot-patterns: パターン集約]
    B --> C{高 confidence?}
    C -- Yes --> D[self-improve Issue 起票]
    C -- No --> E[session.json に記録のみ]
```

### ECC 照合フロー

```mermaid
flowchart TD
    A[自リポジトリ Issue 検出] --> B[doobidoo memory 検索]
    B --> C{関連知見あり?}
    C -- Yes --> D[workflow に知見注入]
    C -- No --> E[通常フロー継続]
```

### 改善適用フロー

```mermaid
flowchart TD
    A[collect: self-improve Issue 収集] --> B[propose: ECC 照合 + 提案]
    B --> C[ユーザー確認]
    C --> D{承認?}
    D -- Yes --> E[close: 適用 + Issue クローズ]
    D -- No --> F[保留]
```

### User-Triggered Review フロー（B-7）

```mermaid
graph LR
    H[PostToolUse Hook] -->|exit_code != 0| L[errors.jsonl]
    U[ユーザートリガー] --> R[self-improve-review]
    R --> L
    R -->|会話コンテキスト参照| A[エラー分析]
    A -->|ユーザー選別| E[explore-summary.md]
    E -->|co-issue Phase 2| I[Issue化]
```

- **機械層**: PostToolUse hook が Bash エラーを `.self-improve/errors.jsonl` に記録（サイレント）
- **判断層**: ユーザーが `/dev:self-improve-review` でトリガー。エラーサマリーから問題を選別
- **Issue化層**: 選別結果を `.controller-issue/explore-summary.md` に書き出し、co-issue のフローに接続

## Constraints

- **cooldown 判定**: 同一パターンの重複 Issue 起票を防止。pattern name + 時間窓でチェック
- **co-autopilot 内で自動起動**: セッション完了時の retrospective で検出
- **ECC ソースの優先度**: doobidoo memory > openspec > git log

## Rules

- **独立 controller なし**: co-autopilot の後処理として統合。「別概念にしない」（設計判断 #2: 旧 controller-self-improve の吸収）
- **confidence 閾値**: HIGH 以上でのみ Issue 起票推奨。MEDIUM 以下は session.json patterns に記録のみ
- **self-improve-format テンプレート準拠**: 起票時は refs/self-improve-format.md の共通フォーマットに従う

### Error Recording ルール
- PostToolUse hook は記録のみ。ブロック・アラート・自動対処を行わない
- errors.jsonl はセッションスコープ（.gitignore 対象）
- テスト実行のエラーも記録される（問題かどうかの判断は人間が行う）
- self-improve-review は co-issue の Phase 1 (explore) の代替として機能する

## Component Mapping

| 種別 | コンポーネント | 役割 |
|------|--------------|------|
| **(co-autopilot 内)** | autopilot-patterns | パターン検出・high confidence 時に Issue 起票 |
| **(co-autopilot 内)** | autopilot-retrospective | Phase 振り返り・知見生成 |
| **atomic** | self-improve-collect | self-improve Issue の収集・分類 |
| **atomic** | self-improve-propose | ECC 照合 + 改善提案生成 |
| **atomic** | self-improve-close | Issue クローズ処理 |
| **atomic** | self-improve-review | エラーログ分析（User-Triggered） |
| **atomic** | ecc-monitor | ECC リポジトリ変更検知 |
| **atomic** | pr-cycle-analysis | PR-cycle 結果からの改善機会検出 |
| **atomic** | session-audit | セッション JSONL 事後分析（5カテゴリ検出） |

**注意**: self-improve は独立 controller を持たない。co-autopilot の後処理として統合されている（ADR-002）。self-improve-review のみがユーザー直接トリガーで、co-issue フローに接続する。

## Dependencies

- **Upstream <- Autopilot**: パターン検出データ（session.json patterns）
- **Upstream <- PR Cycle**: pr-cycle-analysis でパターン検出
- **Downstream -> Issue Management**: self-improve Issue 起票
- **Downstream -> Issue Management**: self-improve-review が co-issue フローに接続（explore-summary.md 経由）
