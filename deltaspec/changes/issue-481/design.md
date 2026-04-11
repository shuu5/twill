## Context

`co-self-improve` SKILL.md Step 1（scenario-run）は test-project-init → scenario-load → session:spawn の 3 ステップで構成される。#479 と #480 で各 atomic がそれぞれ `--mode real-issues` / `--real-issues` フラグを受け取れるようになったが、SKILL.md には引数解析と委譲ロジックが存在しない。また、spawn 後に co-autopilot が test-target worktree で起動される経路が SKILL.md に明文化されていない。

## Goals / Non-Goals

**Goals:**

- `--real-issues --repo <owner>/<name>` フラグを co-self-improve が受け取り、各 atomic に適切に委譲する
- 引数なし / local 指定の場合はローカルモード（従来の動作）を維持する
- 引数が ambiguous な場合に AskUserQuestion で明示的にモードを選択させる
- Step 5 の session:spawn で co-autopilot を明示的に起動する経路を SKILL.md に記述する

**Non-Goals:**

- test-project-init.md / test-project-scenario-load.md の実装変更（#479, #480 で完了）
- observe ループの改修
- session:spawn の内部実装変更

## Decisions

### フラグ解析の位置

SKILL.md Step 1 の冒頭（init 実行前）に `--real-issues` フラグと `--repo` 引数を解析するステップを追加する。

- `--real-issues` フラグあり + `--repo <owner>/<name>` あり → real-issues モード
- `--real-issues` フラグあり + `--repo` なし → AskUserQuestion で `--repo` を質問
- フラグなし（`--local` も含む）→ local モード（従来通り）
- 引数が曖昧（scenario 名だけ等）→ AskUserQuestion で「local / real-issues どちらですか?」

### co-autopilot の明示

Step 5 の `Skill(session:spawn)` 呼び出しに `-- /twl:co-autopilot` を prompt として渡し、test-target worktree で co-autopilot が起動される経路を明文化する。

### 引数フォーマット

`/twl:co-self-improve scenario-run <scenario-name> --real-issues --repo <owner>/<name>` を canonical 呼び出し形式とする。

## Risks / Trade-offs

- **既存動作への影響**: フラグなしは従来の local モードにフォールバックするため、既存の動作は変化しない
- **AskUserQuestion の追加**: 引数が不足する場合にのみ質問するため、明示的な呼び出しでは質問が発生しない
