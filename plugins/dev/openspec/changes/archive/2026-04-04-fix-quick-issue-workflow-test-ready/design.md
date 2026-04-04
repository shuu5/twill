## Context

現状分析:

- `workflow-setup SKILL.md` Step 4 は `IS_AUTOPILOT=true` だけを見て無条件に `/dev:workflow-test-ready` を呼び出す指示になっており、`is_quick` チェックが存在しない
- `autopilot-orchestrator.sh` の `_nudge_command_for_pattern()` には既に quick チェックが実装されているが、"setup chain 完了" テキストを LLM が出力しない場合（SKILL.md が直接 test-ready を呼び出す場合）は機能しない
- `autopilot-launch.sh` の `PROMPT` は常に `/dev:workflow-setup #${ISSUE}` 固定で、quick ラベル情報が Worker に渡されない

根本原因: SKILL.md Step 4 の指示が is_quick を無視して IS_AUTOPILOT=true だけでtransitionするため、LLM が orchestrator の nudge をバイパスして直接 test-ready を呼び出す。

## Goals / Non-Goals

**Goals:**

- quick + IS_AUTOPILOT=true の組み合わせで workflow-test-ready が呼ばれないこと（LLM 指示レベル）
- autopilot-launch.sh が quick ラベルを Worker プロンプトに含めること（情報提供レベル）
- workflow-test-ready に quick 判定ガードを追加すること（defense-in-depth）
- orchestrator nudge の既存 quick チェックが正常機能していることを確認

**Non-Goals:**

- Board 更新・Issue close 修正（別 Issue スコープ）
- deps.yaml の spawnable_by 不整合修正
- quick Issue の merge-gate フロー自体の変更

## Decisions

### D1: SKILL.md Step 4 に is_quick チェックを先行配置

`workflow-setup SKILL.md` Step 4 のシェルスニペットを拡張し、IS_AUTOPILOT チェックより先に is_quick を判定する。quick + autopilot の場合は MUST NOT で workflow-test-ready 呼び出しを禁止し、「直接実装 → commit → push → `gh pr create --fill --label quick` → merge-gate のみ」と明示する。

**理由**: LLM はプロンプトに明示的な MUST NOT がなければ先行する強い命令形に従う。is_quick の判定を先に記述し、禁止句を付けることで指示構造の優先度問題を解消する。

### D2: autopilot-launch.sh に quick ラベル検出と専用プロンプト分岐を追加

`detect_quick_label` 関数（または gh issue view による判定）を launch.sh に追加し、quick ラベルがあれば `PROMPT` に `--label quick` を追記した情報を付与する。

**理由**: Worker LLM が launch 段階から quick Issue であることを知ることで、SKILL.md 読み込み前から適切な文脈で動作できる。

### D3: workflow-test-ready SKILL.md に quick 判定ガードを追加

`workflow-test-ready` の先頭で is_quick 状態を確認し、quick Issue の場合は即座に終了（「quick Issue は workflow-test-ready をスキップしてください」とメッセージを出す）。

**理由**: LLM 指示と orchestrator の両方をすり抜けた場合の最終防衛線（defense-in-depth）。

### D4: orchestrator の既存 quick チェックはそのまま維持

`_nudge_command_for_pattern()` の is_quick チェックは既に正しく実装されているため変更不要。

## Risks / Trade-offs

- **SKILL.md 修正の副作用**: Step 4 の指示構造変更により compaction 復帰時の挙動に影響が出る可能性があるが、is_quick チェックは state-read.sh で機械的に取得するため安定している
- **launch.sh のプロンプト追加**: Worker プロンプトが長くなるが、1 行の情報追加なので影響軽微
- **workflow-test-ready ガード**: quick Issue を誤って通常フローで実行しようとしたとき即時終了するため、手動実行時も影響するが、quick Issue で test-ready が必要なケースはないため問題なし
