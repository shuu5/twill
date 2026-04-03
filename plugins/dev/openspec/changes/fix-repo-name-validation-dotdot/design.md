## Context

`scripts/autopilot-plan-board.sh` の `_build_cross_repo_json` 関数（L89）で、クロスリポジトリ名を検証する正規表現が `^[a-zA-Z0-9_.-]+$` となっており、`..` が通過可能。L85 の owner バリデーション（`^[a-zA-Z0-9_-]+$`）は問題なし。

## Goals / Non-Goals

**Goals:**
- `autopilot-plan-board.sh` L89 の正規表現を修正し `..` および `.` を拒否する

**Non-Goals:**
- `autopilot-plan.sh` L72 の同一パターン修正（スコープ外、別 Issue で対応）
- 他スクリプトのバリデーション見直し

## Decisions

1. **正規表現パターン変更**: `^[a-zA-Z0-9_.-]+$` → `^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$`
   - 先頭文字に `.` を禁止することで `..` が先頭条件で失敗する
2. **明示的拒否条件追加**: `[[ "$cross_name" == ".." || "$cross_name" == "." ]] && continue`
   - 二重の防衛として `.` 単体も拒否

## Risks / Trade-offs

- リスクなし。GitHub リポジトリ名に `..` は実際には使用不可のため、既存動作への影響なし
