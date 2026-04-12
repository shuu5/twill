## Context

- `cli/twl/src/twl/spec/paths.py` の `find_deltaspec_root()` は cwd から上方向に `deltaspec/` ディレクトリを walk-up する
- config.yaml の有無を判定しないため、root の `deltaspec/`（config.yaml なし）を正規の `plugins/twl/deltaspec/` より先に検出してしまう
- `chain-runner.sh` の init ステップも `[[ -d "$root/deltaspec" ]]` でチェックしており同じ問題を持つ
- worktree root から `plugins/twl/` 内の deltaspec を検出するためには walk-down 探索が必要

## Goals / Non-Goals

**Goals:**
- `find_deltaspec_root()` が config.yaml を持つ deltaspec/ のみを有効とする
- worktree root から実行しても `plugins/twl/deltaspec/` が検出される
- root `deltaspec/changes/` 31 件を `plugins/twl/deltaspec/changes/archive/` へ統合
- root `deltaspec/` ディレクトリを削除
- chain に spec-archive ステップを追加（auto-merge.sh + orchestrator）

**Non-Goals:**
- `cli/twl/deltaspec/` の OpenSpec → DeltaSpec 移行
- `.deltaspec.yaml` への issue フィールド追加
- `plugins/session/` の deltaspec 新規作成

## Decisions

### D-1: find_deltaspec_root() ハイブリッド検出

1. **Walk-up**: cwd から上方向に `deltaspec/config.yaml` を探索（config.yaml がない `deltaspec/` はスキップ）
2. **Walk-down fallback**: walk-up で見つからない場合、`git rev-parse --show-toplevel` を起点に `**/deltaspec/config.yaml` をスキャン（maxdepth=3、`.git`/`node_modules`/`__pycache__` 除外）
3. **複数ヒット時**: cwd に最も近いもの（最長共通パス長）を選択
4. **0件**: `DeltaspecNotFoundError` を raise

Rationale: walk-up のみでは root deltaspec がブロッカーになる。walk-down は git toplevel ベースで範囲を制限することで安全性を担保する。

### D-2: twl spec new の config.yaml 自動生成

`twl spec new` 実行時、`deltaspec/` が存在しない場合のみ config.yaml を自動生成する。既存の `deltaspec/` がある場合は何もしない（後方互換）。

config.yaml 最小テンプレート:
```yaml
schema: spec-driven
context: <component-name>
```

### D-3: chain-runner.sh の deltaspec 判定変更

L277 の `[[ -d "$root/deltaspec" ]]` を以下に変更:
```bash
[[ -f "$root/deltaspec/config.yaml" ]] || \
find "$root" -maxdepth 3 -name config.yaml -path '*/deltaspec/*' -print -quit 2>/dev/null | grep -q .
```

### D-4: root deltaspec/changes/ 統合方針

- 31 件を Issue 番号順（issue-323 〜 issue-410）に処理
- `twl spec archive <change>` で `plugins/twl/deltaspec/changes/archive/` へ移動 + specs 統合
- コンフリクト（同一 spec への複数 MODIFIED）は手動レビューで解決
- 統合完了後、root `deltaspec/` を削除

### D-5: auto-merge.sh への spec-archive 追加

squash merge 成功後、`change_id` が存在する場合に:
```bash
twl spec archive "$change_id" --yes
git add plugins/twl/deltaspec/
git commit -m "chore(deltaspec): archive $change_id"
git push
```
spec-archive 失敗はブロッカーとしない（WARNING ログのみ）。

### D-6: orchestrator --skip-specs 除去

`archive_done_issues()` から `--skip-specs` を除去。spec 統合失敗時は `--skip-specs` フォールバック + WARNING ログ（archive 自体はブロックしない）。

## Risks / Trade-offs

- **walk-down 探索コスト**: maxdepth=3 制限と除外ディレクトリリストで軽減
- **31 件の一括統合**: コンフリクトリスクあり。手動レビューフェーズを設ける
- **auto-merge.sh の spec-archive 失敗**: PR merge 後の追加 commit が失敗した場合、specs 統合が skipped になる。ただし archive 自体はブロックしない設計
- **既存テスト**: `pytest tests/` の spec 関連テストが `find_deltaspec_root()` 変更の影響を受ける可能性がある
