## Context

現在の chain 実行では、全ステップで LLM が command.md を Read → 解釈 → 実行している。しかし 11 のステップは純粋な bash ロジック（GraphQL 呼び出し、ファイル存在チェック、スクリプト実行等）であり、LLM の判断を必要としない。これらを bash スクリプトに委譲することで、Worker のトークン消費を削減する。

対象 workflow は 3 つ: workflow-setup、workflow-test-ready、workflow-pr-cycle。

## Goals / Non-Goals

**Goals:**

- chain-runner.sh が 11 の機械的ステップをステップ名指定で実行できる
- Worker が機械的ステップの command.md を Read しなくなる
- 手動実行パス（non-autopilot）で既存 command.md が引き続き動作する
- deps.yaml に chain-runner.sh が登録される

**Non-Goals:**

- loom CLI 本体への `chain run` コマンド追加（loom リポジトリ側）
- LLM 判断を含むステップの script 化（crg-auto-build, post-fix-verify, opsx-propose 等）
- fix ループや merge-gate エスカレーション等のフロー制御の script 化
- quick ラベル / 軽量 chain の対応

## Decisions

### 1. chain-runner.sh はステップ名ディスパッチ方式

chain-runner.sh は `bash chain-runner.sh <step-name> [args...]` で呼び出し、case 文でステップごとの処理にディスパッチする。各ステップの実装は既存 command.md のロジックを bash に移植する。

**理由**: 1 ファイルに集約することで、ステップ間の共通ユーティリティ（ISSUE_NUM 抽出、worktree パス解決等）を関数として共有でき、依存管理が単純になる。

### 2. 既存 command.md は削除しない

command.md は手動実行パス（non-autopilot でユーザーが直接 `/twl:xxx` を呼ぶケース）で引き続き使用される。chain-runner.sh は autopilot chain 内での高速実行パスとして共存する。

**理由**: 手動実行時は LLM がコンテキストを読んで実行すること自体がユーザー体験の一部であり、トークン消費の最適化は不要。

### 3. SKILL.md の chain 実行指示を runner 呼び出しに置換

各 workflow SKILL.md の「chain 実行指示」セクションで、機械的ステップは `bash chain-runner.sh <step>` 呼び出しに変更する。LLM 判断ステップは従来通り command.md Read → 実行。

**理由**: SKILL.md が Worker への指示書であるため、ここを変更するだけで Worker の動作が変わる。

### 4. chain-runner.sh の出力は構造化メッセージ

各ステップは終了時に `✓ <step-name>: <summary>` または `⚠️ <step-name>: <reason>` を stdout に出力する。Worker はこの出力を読むだけで結果を把握できる。

**理由**: Worker が command.md を Read する代わりに、runner の出力を解釈するだけで済むため。

### 5. script 化対象 11 ステップ

| ステップ | 元ソース | workflow |
|---------|---------|---------|
| init | commands/init.md | setup |
| board-status-update | commands/project-board-status-update.md | setup |
| ac-extract | commands/ac-extract.md | setup |
| arch-ref | SKILL.md インライン | setup |
| change-id-resolve | SKILL.md インライン | test-ready |
| worktree-create | scripts/worktree-create.sh（runner 統合） | setup |
| ts-preflight | commands/ts-preflight.md | pr-cycle |
| pr-test | commands/pr-test.md | pr-cycle |
| all-pass-check | commands/all-pass-check.md | pr-cycle |
| pr-cycle-report | commands/pr-cycle-report.md（構造化集約部分） | pr-cycle |
| check | commands/check.md | test-ready |

## Risks / Trade-offs

### bash スクリプトの保守コスト

11 ステップ分のロジックが 1 ファイルに集約されるため、chain-runner.sh が肥大化するリスクがある。ただし各ステップは独立しており、case 文で明確に分離されるため可読性は維持できる。

### command.md との二重管理

同じロジックが command.md と chain-runner.sh の両方に存在することになる。将来的にロジック変更時に片方の更新を忘れるリスクがある。ただし command.md は LLM への指示書であり、chain-runner.sh は bash 実装であるため、役割が異なる。

### all-pass-check の state-write.sh 依存

all-pass-check は issue-{N}.json への状態遷移（merge-ready / failed）を含む。autopilot 配下判定（state-read.sh）と状態書き込み（state-write.sh）の両方を chain-runner.sh 内で処理する必要がある。
