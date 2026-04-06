## Context

`autopilot-orchestrator.sh` の `_nudge_command_for_pattern` 関数（L365-381）は、tmux ペインの出力から chain 停止パターンを検出し次コマンドを決定する。この関数は `is_quick` の概念を持たず、quick ラベル付き Issue でも "setup chain 完了" パターンを検出すると `/twl:workflow-test-ready` を送信してしまう。

`is_quick` の永続化は `chain-runner.sh` の `init` ステップが担当し、`state-read.sh --type issue --issue N --field is_quick` で参照可能。未永続化時の fallback として `detect_quick_label()` (chain-runner.sh L74-84) が gh API で quick ラベルを直接確認できる。

## Goals / Non-Goals

**Goals:**
- `_nudge_command_for_pattern` が quick Issue（`is_quick=true`）で "setup chain 完了" および "workflow-test-ready で次に進めます" パターンをスキップし `return 1`（nudge しない）を返す
- `state-read.sh --field is_quick` を一次取得元とし、未永続化時は gh API fallback で対応
- `orchestrator-nudge.bats` の test double を更新し、quick Issue シナリオのテストを追加

**Non-Goals:**
- 他のパターン（">>> 提案完了"、"テスト準備.*完了" 等）の quick 分岐追加（今回スコープ外）
- `is_quick` の永続化タイミング変更（既存の `init` ステップの動作維持）

## Decisions

### D1: is_quick の取得方法

`_nudge_command_for_pattern` の冒頭で以下の順で `is_quick` を判定する:

1. `bash "$SCRIPTS_ROOT/state-read.sh" --type issue --issue "$issue" --field is_quick 2>/dev/null`
2. 空文字の場合、gh API fallback: `gh issue view "$issue" --json labels --jq '.labels[].name' 2>/dev/null | grep -qxF "quick" && echo "true" || echo "false"`

gh API fallback は `init` ステップより前に orchestrator がポーリングを開始するケースへの保険。毎回 gh API を叩かないよう state ファイルを優先する。

### D2: スキップ対象パターン

test-ready 送信が発生するパターンのみスキップ:
- `setup chain 完了` → `/twl:workflow-test-ready` 送信
- `workflow-test-ready.*で次に進めます` → `/twl:workflow-test-ready` 送信

`>>> 提案完了` と `PR サイクル.*完了` は空文字（`echo ""`）を返すだけで実害がないためスキップ不要。

### D3: test double の更新方針

`orchestrator-nudge.bats` の `nudge-dispatch.sh` は実装と同一ロジックを再現する test double。実装変更に追従して更新する。state-read.sh の stub は `SANDBOX/scripts/state-read.sh` として配置する（common_setup が SANDBOX を設定する既存パターンに従う）。

## Risks / Trade-offs

- **gh API fallback のコスト**: fallback は gh API を呼ぶため低速。state ファイルが正常に書き込まれていれば発生しない想定
- **SCRIPTS_ROOT の前提**: `_nudge_command_for_pattern` 内で `$SCRIPTS_ROOT` が定義済みの前提。orchestrator 本体は起動時に設定しているため問題なし
