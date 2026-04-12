## Context

`workflow-issue-refine/SKILL.md` の Step 3b は spec-review セッションで N Issue × 3 specialist を spawn する手順を記述している。現行機構は LLM ガイダンス（SKILL.md）と hook 自動ゲート（`pre-tool-use-spec-review-gate.sh`）のハイブリッドだが、この責務分離が文書化されていない。

現行スクリプト構成:
- `spec-review-session-init.sh`: state ファイル（`/tmp/.spec-review-session-{hash}.json`）を初期化
- `spec-review-manifest.sh`: 固定 3 specialist リストを出力
- `pre-tool-use-spec-review-gate.sh`: `Skill(issue-review-aggregate)` 呼出前に `completed < total` なら PreToolUse hook で deny

## Goals / Non-Goals

**Goals:**
- `workflow-issue-refine/SKILL.md` Step 3b 冒頭に責務分離ノートを追記
- LLM ガイダンス層と hook 自動ゲート層の責務境界を明記
- hook の deny 発動条件（`completed < total`）を明記
- `spec-review-session-init.sh` の初期化必須性を明記

**Non-Goals:**
- Step 3b / 3c の動作ロジック変更
- スクリプト・hook 自体の変更
- `issue-spec-review.md` の state ファイル更新ロジック追加（別 Issue）

## Decisions

**変更箇所**: `plugins/twl/skills/workflow-issue-refine/SKILL.md` Step 3b 冒頭

**ノート形式**: blockquote（`>`）を使用し、責務分離ノートとして視覚的に区別する

**含める内容**:
1. LLM ガイダンス層 vs hook 自動ゲート層の責務境界
2. `spec-review-session-init.sh` の初期化が必須な理由（不在時の fallthrough）
3. hook deny 発動条件（`completed < total`）
4. `pre-tool-use-spec-review-gate.sh` への参照リンク

## Risks / Trade-offs

- **リスク**: なし（文書化のみで動作変更なし）
- **トレードオフ**: ノート追加により Step 3b の記述が長くなるが、責務分離の明確化という価値がそれを上回る
