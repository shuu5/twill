## Context

su-observer は現状 `cld-observe-loop` を co-autopilot 起動後に能動 observe として利用するが、supervise 1 iteration の中で Monitor tool（Pilot tail streaming）と cld-observe-loop（Worker 群 polling）を**並行実行する手順**が SKILL.md に明示されていない。また observe-once は単一 window の snapshot のみを取得しており、state file の `updated_at` stagnate を確認しない。

`AUTOPILOT_STAGNATE_SEC` 環境変数は #469/#472 で導入される共通閾値。本 Issue では参照のみ（未定義時デフォルト 600s）。

## Goals / Non-Goals

**Goals:**
- su-observer SKILL.md Step 1 に5チャンネル監視マトリクスを追加し、supervise 1 iteration での並行実行手順を明示する
- observe-once に state file mtime チェックロジックを追加し、stagnate 時に WARN を stdout 出力する
- intervention-catalog に pattern-7（Worker idle: stagnate + `>>> 実装完了:` 検出 → Layer 0 Auto）を追加する
- tests/scenarios/ に cld-observe-loop 連携の dry-run テストシナリオを追加する

**Non-Goals:**
- `cld-observe-loop` スクリプト自体の変更（既存 i/f: `--pattern GLOB --interval SECONDS --max-cycles N --notify-dir DIR` を利用するだけ）
- `AUTOPILOT_STAGNATE_SEC` 環境変数の新規実装（#469/#472 に委譲）
- Pilot window 以外への Monitor tool 適用

## Decisions

### D-1: 監視チャンネルマトリクスの配置

SKILL.md Step 1 の**冒頭**に「supervise 1 iteration」セクションとして5チャンネルマトリクスと実行手順を追加する。既存の「controller spawn が必要な場合」セクションより前に置き、supervise の基本ループとして確立する。

### D-2: observe-once の state mtime チェック

observe-once Step 3（session_state 取得）の後に Step 3.5 として追加する:

```bash
# state file mtime チェック
STAGNATE_SEC="${AUTOPILOT_STAGNATE_SEC:-600}"
find .autopilot/issues/ -name "issue-*.json" -mmin +$((STAGNATE_SEC/60)) 2>/dev/null | while read f; do
  echo "WARN: state stagnate detected: $f (>${STAGNATE_SEC}s)"
done
```

JSON 出力に `stagnate_files` 配列フィールドを追加する。

### D-3: pattern-7 の層分類

- 検出: state stagnate（`updated_at` が 600s 以上古い）AND worker pane tail に `>>> 実装完了:` を含む
- 層: **Layer 0 Auto**（明確な完了シグナルがあるため自動回復が安全）
- 介入: `/twl:workflow-pr-verify --spec issue-<N>` を対象 Worker window に inject

### D-4: テストシナリオ形式

`tests/scenarios/su-observer-stagnate-detect.md` として WHEN/THEN 形式で dry-run シナリオを記述する。実際の tmux セッション起動は不要で、state file の mtime を手動操作して observe-once の出力を検証する。

## Risks / Trade-offs

- **find -mmin の精度**: `mmin` は分単位のため 600s（10分）は `+10` だが端数切り捨て。実際は 600〜659s の stagnate を 10 分として扱う。許容範囲。
- **cld-observe-loop との競合**: observe-once の state mtime チェックは read-only のため cld-observe-loop との競合はない。
- **AC-4（Wave 検証）**: 実装後の次 Wave 実行で確認する。本 DeltaSpec では手順の定義のみ。
