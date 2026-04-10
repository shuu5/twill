## Context

`workflow-issue-refine` は複数 Issue に対して `issue-spec-review` を N 回呼ぶループ構造を持つが、このループは現在プロンプト指示のみで保証されている。#445 で各 `issue-spec-review` 内の 3 specialist 追跡（PostToolUse hook によるマニフェスト管理）は復旧するが、N Issue × 3 specialist の全完了をセッションレベルで集約する仕組みは存在しない。

本設計では `/tmp` 上のセッション状態ファイルと PreToolUse hook を組み合わせ、forward progression gate を機械的に実現する。

## Goals / Non-Goals

**Goals:**

- `workflow-issue-refine` が N Issue に対して全 `issue-spec-review` を実行し終えるまで `issue-review-aggregate` への進行を机ブロックする
- セッション state は flock ベースの競合制御で並列書き込みに対応する
- spec-review context 以外（phase-review 等）には一切影響しない

**Non-Goals:**

- 外部オーケストレーター・永続化 DB の導入（後続 Issue で対応）
- issue-spec-review 内のマニフェスト書き出し修正（#445 で対応済み）
- flock なしのシンプルな state 管理（競合制御を省略しない）

## Decisions

### セッション state ファイルの設計

- **パス**: `/tmp/.spec-review-session-{hash}.json`
  - hash 算出: `printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}'`
  - 同一プロジェクト内でセッションをユニークに特定する
- **構造**: `{"total": N, "completed": 0, "issues": {}}`
  - `total`: `spec-review-session-init.sh N` で設定
  - `completed`: specialist 完了ごとにインクリメント
  - `issues`: 将来の拡張用（本 Issue では未使用）
- **競合制御**: `flock /tmp/.spec-review-session-{hash}.lock` で read-modify-write をアトミックに実行

### PreToolUse gate の実装方針

- `hooks.json` の PreToolUse に `"matcher": "Skill"` エントリを追加
- `pre-tool-use-spec-review-gate.sh` は `jq -r '.tool_input.skill'` でスキル名を取得し `issue-review-aggregate` のみをターゲットにする（`pre-tool-use-host-safety.sh` の `tool_input.command` 検査と同パターン）
- `completed < total` の場合: `permissionDecision: "deny"` + 残り Issue 数と `/twl:issue-spec-review` 呼び出し誘導メッセージを返す
- `completed == total` の場合: gate 通過 → state file + lock file をクリーンアップ

### check-specialist-completeness.sh 拡張の方針

- マニフェストファイル名から context を抽出するロジックを既存コードに追加
- `spec-review-` prefix を持つ context の場合のみセッション state を更新する
- 他の context（phase-review など）は既存の動作を維持する

## Risks / Trade-offs

- **`/tmp` のライフサイクル**: プロセス再起動や OS 再起動でセッション state が消える。意図的な設計（一時的なセッション管理）だが、異常終了後にセッションが残留する可能性がある → `spec-review-session-init.sh` が既存 state を上書き初期化することで対処
- **flock のデッドロック**: hook 実行が中断された場合にロックが解放されない可能性がある → `flock -w 5`（タイムアウト付き）を使用
- **セッション state ファイルが存在しない場合**: gate が state ファイルを見つけられない場合はブロックしない（gate miss は安全側のフォールバック）→ 初期化未実施の場合に gate が無効化されるリスクを明示的に受け入れる
