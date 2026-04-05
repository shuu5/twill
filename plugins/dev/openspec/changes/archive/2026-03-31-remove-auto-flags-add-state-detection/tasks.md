## 1. autopilot-launch プロンプト修正

- [x] 1.1 `commands/autopilot-launch.md` Step 3 のプロンプトから `--auto --auto-merge` を除去し `/dev:workflow-setup #${ISSUE}` のみにする

## 2. workflow-setup フラグ除去 + state-read 判定導入

- [x] 2.1 `skills/workflow-setup/SKILL.md` の引数解析セクションから `--auto`/`--auto-merge` を除去
- [x] 2.2 `skills/workflow-setup/SKILL.md` Step 4 の `--auto` 条件を state-read.sh ベースの IS_AUTOPILOT 判定に置換

## 3. opsx-apply フラグ除去 + state-read 判定導入

- [x] 3.1 `commands/opsx-apply.md` から `--auto` モード分岐を除去
- [x] 3.2 `commands/opsx-apply.md` Step 3 チェックポイント出力を state-read.sh ベースの判定に置換

## 4. pr-cycle-analysis フラグ除去 + state-read 判定導入

- [x] 4.1 `commands/pr-cycle-analysis.md` の引数セクションから `--auto` を除去
- [x] 4.2 `commands/pr-cycle-analysis.md` の自動起票判定を state-read.sh ベースに変更

## 5. self-improve-propose フラグ除去 + state-read 判定導入

- [x] 5.1 `commands/self-improve-propose.md` の引数セクションから `--auto` を除去
- [x] 5.2 `commands/self-improve-propose.md` の自動承認判定を state-read.sh ベースに変更

## 6. co-autopilot --auto-merge 除去

- [x] 6.1 `skills/co-autopilot/SKILL.md` から `--auto-merge` への全ての言及を除去（`--auto` は存続）

## 7. openspec 矛盾解消

- [x] 7.1 `openspec/changes/c-2d-autopilot-controller-autopilot/specs/session-management/spec.md` Line 44 のプロンプト記述を修正

## 8. 検証

- [x] 8.1 `commands/` と `skills/` 内で `--auto-merge` の残存がないことを grep で確認
- [x] 8.2 `commands/` と `skills/` 内で引数としての `--auto` の残存がないことを確認（co-autopilot の `--auto` は除外）
- [x] 8.3 `loom check` が PASS することを確認
