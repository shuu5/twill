## Context

Autopilot Worker は tmux window 内の Claude Code セッション（cld）として動作する。Worker は chain steps（workflow-setup → workflow-test-ready → workflow-pr-cycle）を Skill tool で逐次実行する。chain 遷移ポイントでは SKILL.md の「停止するな」テキスト指示に従って次スキルを自動実行する設計だが、LLM の attention に依存するため compaction やコンテキスト長の増大で無視される。

Claude Code の PostToolUse hook は `settings.json` で設定でき、指定 tool 完了後に bash スクリプトを実行して stdout を LLM コンテキストに注入できる。これは SKILL.md テキストより強い機械的保証を提供する。

## Goals / Non-Goals

**Goals:**
- Skill tool 完了後に PostToolUse hook を発火させ、autopilot Worker に次ステップを機械的に注入する
- 非 autopilot セッション（通常利用）への影響をゼロにする
- orchestrator の tmux nudge と競合しないよう `last_hook_nudge_at` で調整する

**Non-Goals:**
- health-check.sh の orchestrator 統合（→ #185）
- SKILL.md のテキスト変更
- chain-runner.sh / chain-steps.sh の変更
- Layer 2 の stall 検知ロジック（→ #185）

## Decisions

### D1: matcher を `"Skill"` に固定

Claude Code の PostToolUse hook は `matcher` フィールドで tool 名を指定する。`"Skill"` 完全一致にすることで、Skill tool 完了後のみ発火し、他 tool への影響を排除する。

### D2: `AUTOPILOT_DIR` 環境変数で autopilot 判定

autopilot-launch.sh が Worker セッション起動時に `AUTOPILOT_DIR` を export する。hook スクリプトはこの変数の存在チェックのみで autopilot 判定を行い、未設定なら即 exit 0。環境変数はプロセス継承されるため、tmux 内の Claude Code セッションで確実に参照できる。

### D3: `chain-runner.sh next-step` で次ステップを機械的に決定

hook が独自に chain 状態を計算することなく、既存の `chain-runner.sh next-step <issue_num> <current_step>` を呼び出す。このコマンドは副作用なし・冪等であり、hook からの安全な呼び出しが保証される。

### D4: stdout に単行テキストを出力して LLM コンテキストに注入

PostToolUse hook の stdout は LLM コンテキストに直接注入される（Claude Code の仕様）。出力は `[chain-continuation] 次は /dev:<skill> を Skill tool で実行せよ。停止するな。` の単行とし、HTML/シェルインジェクションを防ぐためサニタイズする（英数字・`/:-_` のみ許可）。

### D5: `last_hook_nudge_at` を `issue-{N}.json` に記録

hook 注入のたびに ISO 8601 タイムスタンプを `state-write.sh` で記録する。orchestrator の `check_and_nudge()` はこのフィールドを読み取り、直近 `NUDGE_TIMEOUT`（30s）以内に hook 注入があれば tmux nudge をスキップする。これにより同一 stall への二重 nudge を防止する。

### D6: timeout 5000ms、エラー時 exit 0

hook 失敗が Worker を止めてはならない。`chain-runner.sh next-step` は軽量クエリ（JSON ファイル読み取りのみ）のため 5000ms で十分。エラーは stderr にログ出力し、常に exit 0 で終了する。

## Risks / Trade-offs

- **hook 注入の過剰発火**: Skill tool 完了ごとに発火するため、autopilot 配下で非 chain 系スキルを実行した場合も注入が起きる可能性がある。`next-step` が `"done"` を返せば何も出力しないため、実害は限定的。
- **`AUTOPILOT_DIR` export 漏れ**: autopilot-launch.sh が `AUTOPILOT_DIR` を export していない場合、hook が透過的になる（フォールスルー）。launch.sh の既存実装を確認し、未設定の場合は launch.sh に追記が必要。
- **state-write.sh のフィールド追加**: `last_hook_nudge_at` は新フィールド。state-write.sh が未知フィールドを拒否する場合は追記が必要。既存の実装をレビューして対応する。
