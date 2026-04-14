## Context

`merge-gate.md` は TWiLL autopilot の PR マージ判定 controller であり、原則 2.5（controller は 120 行以下推奨）を超える 180 行を持つ。インライン bash スクリプト 6 ブロックがファイル行数の大部分を占め、controller の役割（component 指示）と実装詳細が混在している。既存の他スクリプト（例: `pr-review-manifest.sh`）はすでに `${CLAUDE_PLUGIN_ROOT}/scripts/` 配下に配置されており、参照呼び出しのパターンは確立済みである。

## Goals / Non-Goals

**Goals:**

- `merge-gate.md` を 120 行以下に削減する
- 6 つのインライン bash ブロックをそれぞれ独立したスクリプトファイルへ抽出する
- 各スクリプトの呼び出しは `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"` 形式で統一する
- 動作の等価性を維持する（純粋なリファクタリング）

**Non-Goals:**

- スクリプトのロジック変更・機能追加
- テストの追加
- merge-gate の動作フローの変更

## Decisions

**D1: スクリプト命名規則 — `merge-gate-<role>.sh`**  
既存スクリプト（`pr-review-manifest.sh`, `resolve-issue-num.sh` 等）の命名規則に合わせ、プレフィックス `merge-gate-` で merge-gate 専用スクリプトであることを明示する。

抽出するスクリプト一覧:
| スクリプト名 | 役割 | 元の行番号 |
|---|---|---|
| `merge-gate-check-pr.sh` | PR 存在確認 | L20-29 |
| `merge-gate-build-manifest.sh` | 動的レビュアー構築 | L39-50 |
| `merge-gate-check-spawn.sh` | spawn 完了確認 | L79-91 |
| `merge-gate-cross-pr-ac.sh` | Cross-PR AC 検証 | L118-129 |
| `merge-gate-checkpoint-merge.sh` | checkpoint 統合 | L136-140 |
| `merge-gate-check-phase-review.sh` | phase-review 必須チェック | L149-154 |

**D2: 環境変数の受け渡し**  
スクリプト内で必要な変数（`MANIFEST_FILE`, `SPAWNED_FILE`, `ISSUE_NUM` 等）は、環境変数またはスクリプト引数で受け渡す。`merge-gate.md` 内の変数代入部分はスクリプト呼び出し前に保持する。

**D3: 削減目標 — 120 行以下**  
各ブロック置換後のインライン参照は 1〜3 行で済むため、180 行 → 約 90〜100 行への削減を見込む。

## Risks / Trade-offs

- **環境変数スコープ**: bash スクリプト内で `export` しない変数は子プロセスへ引き継がれないため、必要な変数の `export` を明示する必要がある
- **後方互換**: スクリプトファイルへの分割により、将来的な個別テストが容易になるが、本変更では既存動作の等価性維持を優先する
