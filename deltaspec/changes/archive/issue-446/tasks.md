## 1. 新規スクリプト作成

- [x] 1.1 `plugins/twl/scripts/spec-review-session-init.sh` を新規作成（total 引数でセッション state ファイルを初期化、flock 対応）
- [x] 1.2 `plugins/twl/scripts/hooks/pre-tool-use-spec-review-gate.sh` を新規作成（Skill/issue-review-aggregate を検出し completed < total なら deny）

## 2. 既存スクリプト拡張

- [x] 2.1 `plugins/twl/scripts/hooks/check-specialist-completeness.sh` に spec-review context フィルタを追加（3/3 完了時に `spec-review-` prefix context のみ completed をインクリメント）

## 3. hooks.json 登録

- [x] 3.1 `plugins/twl/hooks/hooks.json` の PreToolUse に `"matcher": "Skill"` + `pre-tool-use-spec-review-gate.sh` エントリを追加

## 4. SKILL.md・アーキテクチャ更新

- [x] 4.1 `plugins/twl/skills/workflow-issue-refine/SKILL.md` の Step 3b 冒頭に `spec-review-session-init.sh <N>` 呼び出しを追加
- [x] 4.2 `plugins/twl/architecture/domain/contexts/issue-mgmt.md` の Constraints セクションに制約 IM-7 を追記

## 5. deps.yaml 更新

- [x] 5.1 `plugins/twl/deps.yaml` に `spec-review-session-init` (script) と `pre-tool-use-spec-review-gate` (script) エントリを追加
- [x] 5.2 `loom check` でグラフ整合性を確認（OK: 227, Missing: 0）

## 6. 動作確認

- [x] 6.1 `spec-review-session-init.sh 3` が state ファイルを正しく作成することを確認
- [x] 6.2 `completed < total` の状態で `issue-review-aggregate` が deny されることを確認
- [x] 6.3 `completed == total` の状態で gate が通過し state ファイルが削除されることを確認
