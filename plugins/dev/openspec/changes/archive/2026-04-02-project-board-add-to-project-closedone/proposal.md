## Why

Issue 起票と Project Board 登録が別作業のため登録漏れが頻発している。GitHub Actions で自動化し、Issue のライフサイクルと Board Status を同期させる。

## What Changes

- `.github/workflows/add-to-project.yml` を新規作成（Issue open 時に Board 自動追加）
- `.github/workflows/project-status-done.yml` を新規作成（Issue close 時に Status → Done）
- PAT 作成・Secret 登録手順を PR description に記載

## Capabilities

### New Capabilities

- Issue opened/reopened/transferred 時に Project Board へ自動追加
- Issue closed 時に Project Board Status を自動的に Done に更新
- Board 未登録 Issue の close 時は graceful スキップ（workflow green）

### Modified Capabilities

なし

## Impact

- `.github/workflows/` に 2 ファイル追加
- リポジトリ Secret `ADD_TO_PROJECT_PAT` が必要（手動登録）
- 既存コードへの影響なし
