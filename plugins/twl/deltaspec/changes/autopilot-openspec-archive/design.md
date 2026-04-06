## Context

autopilot ワークフローには以下の断絶がある:

| コンポーネント | 問題 |
|---|---|
| `auto-merge.sh` L128-133 | autopilot モードで `exit 0` → archive セクション（L153+）未到達 |
| `merge-gate-execute.sh` L163 | 「Archive は autopilot Phase 完了処理が担う」コメントのみ、実装なし |
| `autopilot-orchestrator.sh` `archive_done_issues()` | board-archive のみ実行、deltaspec archive なし |
| `auto-merge.sh` L159 | 非 autopilot パスで `ls ... | head -1`（アルファベット順最初の change を選択、Issue と無関係） |

`.openspec.yaml` に `issue` フィールドを追加することで change と Issue の機械的マッピングを実現する。

## Goals / Non-Goals

**Goals:**
- `archive_done_issues()` に deltaspec archive ステップを追加し、autopilot Phase 完了時に自動アーカイブ
- `.openspec.yaml` に `issue` フィールドを追加して 1 change : 1 Issue の関係を記録
- `auto-merge.sh` L159 の `head -1` を Issue 番号ベースの change 特定に置換
- `merge-gate-execute.sh` L163 コメントと実装を一致させる

**Non-Goals:**
- deltaspec CLI 自体のバグ修正（shuu5/deltaspec#1）
- 既存 orphaned changes の一括アーカイブ
- Context Map への DeltaSpec 統合ポイント追記

## Decisions

### 1. change 特定方法: `.openspec.yaml` の `issue` フィールドを grep

`archive_done_issues()` が Issue 番号を受け取り、全 change の `.openspec.yaml` を grep して対応する change を特定する。

```bash
find openspec/changes -name ".openspec.yaml" -exec grep -l "^issue: ${ISSUE_NUM}$" {} \;
```

### 2. 失敗時は WARNING で継続（board-archive と同パターン）

deltaspec archive 失敗はクリティカルでない。`2>/dev/null` は使わずエラーを >&2 に出力し、次の Issue へ継続。

### 3. `issue` フィールド未設定の change はスキップ + WARNING

コマンドなどの軽微変更で Issue 紐づけがない change を誤アーカイブしないため。

### 4. deltaspec CLI 未インストール時は WARNING でスキップ

```bash
if ! command -v deltaspec >/dev/null 2>&1; then
  echo "[orchestrator] ⚠️ deltaspec CLI が見つかりません" >&2
  return 0
fi
```

### 5. `auto-merge.sh` の change 特定: `.openspec.yaml` の `issue` フィールドを使用

`ISSUE_NUM` が設定されている場合は issue フィールドで特定、未設定の場合は従来の `head -1` を維持（後退互換）。

## Risks / Trade-offs

- **deltaspec archive のインターフェース**: `deltaspec archive <change-id> --yes --skip-specs` を使用（auto-merge.sh の既存パターンを踏襲）
- **worktree 内での deltaspec 実行**: archive は main/ で実行する必要がある可能性あり（worktree から実行すると別ブランチのファイルを参照する）→ archive は `git rev-parse --show-toplevel` 相対で解決
- **複数 change の場合**: 全件アーカイブ（WARNING ログ）。Issue に複数 change を紐づけるケースは稀
