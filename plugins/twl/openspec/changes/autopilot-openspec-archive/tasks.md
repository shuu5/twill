## 1. autopilot-orchestrator.sh: archive_done_issues() に deltaspec archive 追加

- [x] 1.1 `archive_done_issues()` に deltaspec CLI 存在チェック（`command -v deltaspec`）を追加、未インストール時は WARNING でスキップ
- [x] 1.2 `.openspec.yaml` の `issue` フィールドで対応 change を特定するロジックを追加（`find openspec/changes -name ".openspec.yaml" -exec grep -l "^issue: ${issue}$"` パターン）
- [x] 1.3 特定した change に対して `deltaspec archive <change-id> --yes --skip-specs` を実行（失敗時は WARNING で継続）
- [x] 1.4 `issue` フィールド未設定の change は WARNING ログ付きでスキップ

## 2. auto-merge.sh: Issue 番号ベースの change 特定

- [x] 2.1 `CHANGE_ID=$(ls openspec/changes/ ... | head -1)` を `issue` フィールドベースの特定ロジックに置換
- [x] 2.2 `ISSUE_NUM` が未設定の場合は従来ロジック（`head -1`）にフォールバック（後退互換）

## 3. merge-gate-execute.sh: コメント更新

- [x] 3.1 L163 のコメント「Archive は autopilot Phase 完了処理が担う」を実装と一致するよう更新（autopilot は orchestrator、非 autopilot は auto-merge.sh が担う旨を明記）

## 4. .openspec.yaml: issue フィールド追加

- [x] 4.1 `autopilot-openspec-archive` 自身の `.openspec.yaml` に `issue: 235` を追加

## 5. 検証

- [x] 5.1 `loom check` を実行してエラーがないことを確認
- [x] 5.2 `loom update-readme` を実行
