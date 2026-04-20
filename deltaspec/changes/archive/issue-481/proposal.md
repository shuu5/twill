## Why

`co-self-improve` SKILL.md の scenario-run モード Step 1 は、test-project-init と test-project-scenario-load を常にローカルモードで呼び出す。Issue C (#479) と Issue D (#480) で `--mode real-issues` / `--real-issues` フラグが実装されたが、co-self-improve からそれらを起動する経路がなく、実 GitHub Issue を使った end-to-end シナリオ実行が不可能な状態にある。

## What Changes

- `plugins/twl/skills/co-self-improve/SKILL.md` Step 1 に `--real-issues` フラグ受け入れロジックを追加
- 引数なし / ambiguous 時に AskUserQuestion（local vs real-issues）を挿入
- `--real-issues` 時に `test-project-init.md` へ `--mode real-issues --repo <owner>/<name>` を委譲
- `--real-issues` 時に `test-project-scenario-load.md` へ `--real-issues` フラグを委譲
- Step 5 の `session:spawn` で co-autopilot を test-target worktree で起動する経路を明文化

## Capabilities

### New Capabilities

- **real-issues モード**: `/twl:co-self-improve scenario-run <scenario> --real-issues --repo <owner>/<name>` で end-to-end 実行が可能になる
- **モード選択 UX**: 引数が ambiguous な場合に AskUserQuestion で local / real-issues を選択させる

### Modified Capabilities

- **scenario-run Step 1**: フラグを受け取り、init と scenario-load の呼び出しに適切な引数を渡すよう拡張

## Impact

- `plugins/twl/skills/co-self-improve/SKILL.md` — Step 1 を拡張（約 20 行追加）
- 他ファイルへの変更なし（atomic は #479, #480 で実装済み）
