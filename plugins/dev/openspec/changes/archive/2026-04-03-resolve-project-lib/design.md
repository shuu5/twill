## Context

Project Board 操作を行う5箇所のスクリプトが、リポジトリにリンクされた Project を GraphQL で検出するロジックを重複して保持している（`scripts/chain-runner.sh` 2箇所、`scripts/project-board-archive.sh`、`scripts/project-board-backfill.sh`、`scripts/autopilot-plan-board.sh`）。各呼び出し元は戻り値インターフェースがわずかに異なるが、コアロジックは同一。

## Goals / Non-Goals

**Goals:**
- `scripts/lib/resolve-project.sh` に `resolve_project` 共通関数を作成
- 5箇所全ての呼び出し元をリファクタリング
- `mapfile -t` パターンによる word-split 安全化（#141 同時解決）
- `resolve_project` の stdout インターフェースを `project_num project_id owner repo_name repo_fullname` の5値に統一

**Non-Goals:**
- standalone スクリプト（project-board-archive.sh, project-board-backfill.sh）の呼び出しインターフェース変更
- GitHub GraphQL API スキーマの変更
- エラーメッセージの変更

## Decisions

### 1. stdout 5値返却パターン

`resolve_project` は stdout に `project_num project_id owner repo_name repo_fullname` を空白区切りで出力する。呼び出し元は `read -r project_num project_id owner repo_name repo_fullname < <(resolve_project)` パターンで受け取る。

**理由**: `autopilot-plan-board.sh` の既存インターフェースを踏まえ、project_id も返す設計にすることで全呼び出し元をカバーできる。

### 2. source パターン

各スクリプトは `source "${SCRIPT_DIR}/lib/resolve-project.sh"` で読み込む。

**理由**: サブシェル実行ではなく関数として呼び出すことで、将来の拡張（キャッシュ等）に対応しやすい。

### 3. エラーハンドリング

`resolve_project` 内でエラーが発生した場合は stderr にメッセージを出力し、空の stdout を返して非ゼロ終了コードを返す。呼び出し元は終了コードで判断する。

**理由**: chain-runner.sh の `skip` 関数パターンを維持しつつ、共通関数として再利用可能にする。

### 4. mapfile パターン採用

```bash
mapfile -t project_nums < <(echo "$projects" | jq -r '.projects[].number')
[[ ${#project_nums[@]} -eq 0 ]] && return 1
```

**理由**: #141 で確立されたパターンを一貫して適用し、word-split 問題を解消する。

## Risks / Trade-offs

- **テスト範囲**: 共通関数への集約により、単一障害点が生じる。ただし5箇所の重複より安全。
- **SCRIPT_DIR の解決**: 各スクリプトが異なるディレクトリから source する場合、`SCRIPT_DIR` の解決方法を統一する必要がある。`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` パターンを lib 内で使用しない（呼び出し元の SCRIPT_DIR に依存）。
