## Context

loom-plugin-dev リポジトリの Issue ライフサイクルを GitHub Project Board（#3: loom-dev-ecosystem）と自動同期する。Project Board の ID 群は Issue #114 で確定済み。

- Project URL: `https://github.com/users/shuu5/projects/3`
- Project ID: `PVT_kwHOCNFEd84BS03g`
- Status field ID: `PVTSSF_lAHOCNFEd84BS03gzhAPzog`
- Done option ID: `98236657`

## Goals / Non-Goals

**Goals:**

- Issue opened/reopened/transferred → Board 自動追加
- Issue closed → Status を Done に自動更新
- Board 未登録 Issue の close でも workflow が green で完了
- PAT セットアップ手順を PR description に明記

**Non-Goals:**

- loom, loom-plugin-session への workflow 配置（別 Issue）
- 既存 Issue のバックフィル
- Project Board の動的検出（CI 用途のため ID ハードコード）

## Decisions

1. **add-to-project**: `actions/add-to-project` Action を使用。公式かつメンテナンスされており、最小構成で Board 追加が可能。
2. **project-status-done**: `gh api graphql` で直接 mutation を実行。専用 Action が不要で、Item 検索 → 条件付き更新のフローを YAML 内で完結できる。
3. **ID ハードコード**: 動的検出は不要。CI 環境では安定性を優先し、Project 移行時に YAML を更新する運用で十分。
4. **Secret 名統一**: `ADD_TO_PROJECT_PAT` を 3 リポ共通で使用。将来の loom, loom-plugin-session での workflow 追加時にも同じ Secret 名を使える。

## Risks / Trade-offs

- Project Board の ID 変更時に YAML の手動更新が必要（発生頻度は低い）
- PAT の有効期限管理が必要（Fine-grained PAT の場合、最大 1 年）
- `actions/add-to-project` のメジャーバージョン更新時に Dependabot 等での追従が必要
