## Why

co-autopilot は現在 `--issues` or `--explicit` で Issue 番号を手動指定する必要がある。Project Board に Todo/In Progress の Issue があっても手動でリストアップしなければならず、Board が SSOT として機能していない。

## What Changes

- `autopilot-plan.sh` に `--board` モードを追加し、Board の非 Done Issue を自動取得して plan.yaml を生成
- `co-autopilot` SKILL.md の Step 0 引数解析テーブルに `--board` パターンを追加
- Board item の `content.repository` からクロスリポジトリ `--repos` JSON を自動構築

## Capabilities

### New Capabilities

- `--board` モード: `gh project item-list` で Board の非 Done（Todo + In Progress）Issue を取得し、既存の `parse_issues()` に渡して plan.yaml を生成
- クロスリポジトリ Issue 自動解決: Board item の `content.repository` フィールドから `repo_id#number` 形式と `--repos` JSON を自動構築
- Board 空時のエラーハンドリング: 非 Done Issue がない場合はエラーメッセージで正常終了

### Modified Capabilities

- `autopilot-plan.sh` の引数解析: `--board` モードを追加（`--explicit`/`--issues` と排他）
- `co-autopilot` SKILL.md Step 0: `--board` パターンの引数解析ルール追加

## Impact

- **変更ファイル**: `scripts/autopilot-plan.sh`, `skills/co-autopilot/SKILL.md`
- **依存**: #114（loom-plugin-dev: add-to-project + close→Done + PAT 設定）が先行完了必須（Board API アクセスに project scope が必要）
- **API**: `gh project item-list <num> --owner <owner> --format json` を使用
- **既存機能への影響**: `--issues`/`--explicit` モードは変更なし（排他オプションとして共存）
