## 1. autopilot state スキーマ拡張

- [x] 1.1 `implementation_pr` フィールドのサポートを autopilot state (twl.autopilot.state) に追加
- [x] 1.2 `deltaspec_mode` フィールド（`retroactive` / 未設定）のサポートを追加

## 2. chain-runner.sh の retroactive 検出

- [x] 2.1 `init` ステップで `git diff origin/main...HEAD` を解析して実装コードの変更有無を判定するロジックを追加
- [x] 2.2 実装コードがゼロかつ DeltaSpec のみの場合に `deltaspec_mode=retroactive` を設定
- [x] 2.3 `retroactive` 検出時に `recommended_action=retroactive_propose` を返す
- [x] 2.4 Issue body から `Implemented-in: #<N>` タグを検出して `implementation_pr` を自動設定するロジックを追加

## 3. workflow-setup の retroactive フロー

- [x] 3.1 `SKILL.md` に「retroactive DeltaSpec パターン」の説明を追加
- [x] 3.2 `recommended_action=retroactive_propose` の場合の分岐を chain 実行指示に追加
- [x] 3.3 `implementation_pr` が未検出の場合にユーザーへ確認を促すプロンプトを追加

## 4. merge-gate の cross-PR AC 検証

- [x] 4.1 `implementation_pr` が設定されている場合に参照 PR のマージコミットを取得するロジックを追加
- [x] 4.2 `gh pr view <implementation_pr> --json mergeCommit` でコミット SHA を取得して AC 検証に使用
- [x] 4.3 cross-PR 検証結果を merge-gate レポートに記録（`verified_via_pr: <N>` フィールド）

## 5. ドキュメント・テスト

- [x] 5.1 `workflow-pr-verify/SKILL.md` に cross-PR AC 検証モードの説明を追加
- [x] 5.2 retroactive モードの動作を確認する手動テスト（Issue #397 自身で検証）
