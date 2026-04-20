## Why

`co-issue/SKILL.md` Phase 1 が `/twl:explore` を 1 回だけ呼び出して即 Phase 2 に進む設計のため、ユーザーが「まだ掘り下げたい」と伝える構造的機会がない。結果として曖昧な要望のまま後続 Phase に突入し、仕様ギャップ・手戻り・CRITICAL findings 連発という悪循環が生じている。

## What Changes

- `plugins/twl/skills/co-issue/SKILL.md`: Phase 1 を複数回の `/twl:explore` 呼び出しを許容するループ構造に改修。ループ後に AskUserQuestion (loop-gate) を設置し `[A] Phase 2 へ / [B] 追加探索 / [C] 手動編集` を選択させる
- `plugins/twl/tests/scenarios/co-issue-skill.test.sh`: explore ループ構造の 4 ケースを追加

## Capabilities

### New Capabilities

- **explore loop gate**: Phase 1 で 1 回以上の探索後に `[A] Phase 2 へ / [B] 追加探索 / [C] explore-summary.md 手動編集` をユーザーに提示するループ制御
- **accumulated_concerns 再注入**: `[B]` 選択時にユーザーの追加懸念を XML エスケープして次の `/twl:explore` 呼び出しに注入
- **edit-complete-gate**: `[C]` 選択後に `[A] 編集完了 / [B] キャンセル` を再提示し、編集完了を明示確認
- **Step 1.5 ループ外配置**: `/twl:issue-glossary-check` をループ終了（`[A]` 選択）後に 1 度だけ発火させる（呼称 `Step 1.5` に統一）

### Modified Capabilities

- **Phase 1 explore フロー**: 単発呼び出しからループ構造へ変更。既存セッション継続（`[A] 継続`）時の Phase 1 スキップ動作は維持

## Impact

- `plugins/twl/skills/co-issue/SKILL.md` の Phase 1 セクション（L35-39 周辺）のみ改修
- `plugins/twl/tests/scenarios/co-issue-skill.test.sh` にテストケース追加
- Phase 2 以降・`/twl:explore` 本体・他 workflow skill への変更なし
