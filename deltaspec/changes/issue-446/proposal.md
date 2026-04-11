## Why

`workflow-issue-refine` が複数 Issue に対して `issue-spec-review` を N 回呼ぶという外側ループの保証がプロンプトベースのみであり、LLM が Issue 数を削減しても forward progression が可能な状態になっている。セッションレベルの完了数追跡 + PreToolUse deny ゲートにより、全 Issue のレビュー完了を機械的に強制する。

## What Changes

- 新規 `scripts/spec-review-session-init.sh`: Issue 数を受け取りセッション状態ファイル（`/tmp/.spec-review-session-{hash}.json`）を作成
- 新規 `scripts/hooks/pre-tool-use-spec-review-gate.sh`: PreToolUse で `Skill(issue-review-aggregate)` を `completed < total` 時に deny
- `scripts/hooks/check-specialist-completeness.sh` 拡張: 3/3 specialist 完了時に spec-review context のみセッション state の completed を flock 付きでインクリメント
- `hooks/hooks.json`: PreToolUse エントリに `"matcher": "Skill"` + gate hook を追加登録
- `skills/workflow-issue-refine/SKILL.md`: Step 3b 冒頭にセッション初期化ステップを追加
- `architecture/domain/contexts/issue-mgmt.md`: 制約 IM-7（specialist spawn の機械的保証）を追記
- `deps.yaml`: `spec-review-session-init`, `pre-tool-use-spec-review-gate` を script エントリとして追加

## Capabilities

### New Capabilities

- **セッション状態管理**: `spec-review-session-init.sh N` でセッション state ファイルを初期化し、N Issue 分の completed カウントを管理する
- **PreToolUse gate**: `pre-tool-use-spec-review-gate.sh` が `Skill` ツール呼び出し時に `issue-review-aggregate` を検出し、`completed < total` なら deny（残り Issue 数と `issue-spec-review` 呼び出し指示を添える）

### Modified Capabilities

- **自動完了検知の拡張**: `check-specialist-completeness.sh` が 3/3 specialist 完了時に spec-review context の場合にのみセッション state の completed を flock 付きでインクリメント（他コンテキストへの影響なし）
- **workflow-issue-refine**: Step 3b 冒頭に `spec-review-session-init.sh` 呼び出しを追加し、Issue 数でセッションを初期化する

## Impact

- `plugins/twl/scripts/` — 新規スクリプト 2 ファイル追加（spec-review-session-init.sh, pre-tool-use-spec-review-gate.sh）
- `plugins/twl/scripts/hooks/check-specialist-completeness.sh` — セッション state インクリメントロジック追加
- `plugins/twl/hooks/hooks.json` — PreToolUse hook エントリ追加
- `plugins/twl/skills/workflow-issue-refine/SKILL.md` — セッション初期化ステップ追加
- `plugins/twl/architecture/domain/contexts/issue-mgmt.md` — 制約 IM-7 追記
- `plugins/twl/deps.yaml` — 2 エントリ追加
- `#445` の PostToolUse hook が前提条件（マニフェスト追跡機能が存在する必要がある）
