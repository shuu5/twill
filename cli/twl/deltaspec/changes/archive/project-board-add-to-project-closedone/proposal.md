## Why

twill リポジトリで Issue 作成時に自動で Project Board (twill-ecosystem) に追加し、Issue クローズ時に Status を Done に更新する GitHub Actions workflow が未整備。手動管理は漏れが発生しやすく、開発フローの自動化が必要。

## What Changes

- `.github/workflows/add-to-project.yml` を新規作成（Issue → Project Board 自動追加）
- `.github/workflows/project-status-done.yml` を新規作成（Issue close → Status Done 自動更新）

## Capabilities

### New Capabilities

- Issue opened/reopened/transferred 時に Project Board へ自動追加
- Issue closed 時に Project Board の Status を Done に自動遷移
- Board に未登録の Issue を close した場合、workflow が success で完了（エラーなし）

### Modified Capabilities

なし

## Impact

- 新規ファイル: `.github/workflows/add-to-project.yml`, `.github/workflows/project-status-done.yml`
- 依存: `ADD_TO_PROJECT_PAT` Secret（plugins/twl#114 で登録予定）
- 既存コードへの影響なし
