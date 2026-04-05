## Context

B-3 で統一状態管理基盤が構築済み:
- `scripts/state-read.sh` / `state-write.sh`: issue-{N}.json / session.json の読み書き（遷移バリデーション付き）
- `scripts/autopilot-init.sh`: .autopilot/ 初期化 + セッション排他制御
- `scripts/session-create.sh`: session.json 新規作成
- `scripts/session-archive.sh`: セッション完了時アーカイブ
- `scripts/session-add-warning.sh`: cross-issue 警告追記
- `scripts/crash-detect.sh`: Worker crash 検知（tmux ペイン消失 → failed 遷移）

旧プラグインの 11 コンポーネントはマーカーファイル (.done/.fail/.merge-ready) と DEV_AUTOPILOT_SESSION 環境変数で状態管理。これらを B-3 スクリプト群に置換する。

co-autopilot SKILL.md は既に新アーキテクチャ（chain-driven, autopilot-first）で書かれているが、calls に self-improve 系 4 コマンドのみ。11 コマンドを追加する。

## Goals / Non-Goals

**Goals:**

- 全 11 コンポーネントを `commands/<name>.md` 形式で作成
- マーカーファイル参照を state-read.sh / state-write.sh 呼び出しに完全置換
- DEV_AUTOPILOT_SESSION 環境変数を廃止し、state-read --type session での状態確認に置換
- deps.yaml に 11 コマンド定義を追加し co-autopilot calls を更新
- 9 件の不変条件との整合性を維持
- loom validate pass

**Non-Goals:**

- autopilot-plan.sh の作成（別 Issue スコープ）
- autopilot-should-skip.sh の作成（別 Issue スコープ）
- B-3 スクリプト自体の変更（既に完成済み）
- co-autopilot SKILL.md のフロー変更（呼び出し先の追加のみ）

## Decisions

### D1: マーカーファイル → state-read/state-write 置換パターン

| 旧パターン | 新パターン |
|---|---|
| `[ -f "$MARKER_DIR/${ISSUE}.done" ]` | `$(state-read.sh --type issue --issue $ISSUE --field status) == "done"` |
| `[ -f "$MARKER_DIR/${ISSUE}.fail" ]` | `$(state-read.sh --type issue --issue $ISSUE --field status) == "failed"` |
| `[ -f "$MARKER_DIR/${ISSUE}.merge-ready" ]` | `$(state-read.sh --type issue --issue $ISSUE --field status) == "merge-ready"` |
| `cat > "$MARKER_DIR/${ISSUE}.done" <<EOF` | `state-write.sh --type issue --issue $ISSUE --role pilot --set status=done` |
| `cat > "$MARKER_DIR/${ISSUE}.fail" <<EOF` | `state-write.sh --type issue --issue $ISSUE --role pilot --set status=failed` |
| `touch "$MARKER_DIR/${ISSUE}.running"` | `state-write.sh --type issue --issue $ISSUE --role worker --init` |

理由: state-write.sh は遷移バリデーション付きで不正遷移を防止。マーカーファイルの TOCTOU 問題を解消。

### D2: DEV_AUTOPILOT_SESSION 廃止

旧: `export DEV_AUTOPILOT_SESSION=1` で Worker に autopilot 配下であることを通知
新: Worker 起動時に `state-write.sh --type issue --issue $ISSUE --role worker --init` で issue-{N}.json を作成。Worker 内の pr-cycle は `state-read.sh --type issue --issue $ISSUE --field status` で自身が autopilot 配下かを判定。

理由: 環境変数は子プロセスに意図せず伝播するリスクがある。状態ファイルは明示的かつ監査可能。

### D3: crash-detect.sh の活用

旧: autopilot-poll 内で tmux ペイン死亡チェック + .fail マーカー書き込み
新: `crash-detect.sh --issue $ISSUE --window $WINDOW_NAME` を呼び出し。スクリプトが tmux チェック + state-write (status=failed) を一括処理。

理由: crash 検知ロジックの重複を排除。crash-detect.sh は state-write の遷移バリデーションを通すため不正遷移が起きない。

### D4: session-add-warning.sh の活用

旧: autopilot-cross-issue で CROSS_ISSUE_WARNINGS bash 連想配列に直接書き込み
新: `session-add-warning.sh --issue $ISSUE --warning "$MSG"` で session.json の cross_issue_warnings に追記。

理由: session.json への書き込みを一元化し、並行書き込み時の競合を防止。

### D5: コマンド粒度の維持

旧プラグインの 11 コマンド構成をそのまま維持。co-autopilot → autopilot-phase-execute → (autopilot-launch, autopilot-poll, merge-gate) のチェーン呼び出し構造を保持。

理由: 各コマンドが単一責任であり、テスタビリティとデバッガビリティを維持。

### D6: autopilot-init の二重化回避

旧プラグインの autopilot-init（pr-cycle Step 1.9 のマーカー初期化）と B-3 の autopilot-init.sh（.autopilot/ 初期化）は名前が同じだが責務が異なる。新コマンド autopilot-init は B-3 の autopilot-init.sh + session-create.sh のラッパーとし、旧 pr-cycle Step 1.9 の責務は auto-merge コマンド内に吸収。

理由: .autopilot/ 初期化とセッション作成は autopilot 開始時の一回限り。pr-cycle 内のマーカー初期化は state-write --init に置換済み。

## Risks / Trade-offs

### R1: autopilot-plan.sh / autopilot-should-skip.sh の不在

これらは別 Issue スコープだが、autopilot-phase-execute が参照する。本 Issue では参照箇所を記述するが、スクリプト未存在時はエラーメッセージを出力して該当 Issue をスキップする防御的実装とする。

### R2: 旧マーカー形式への後方互換性なし

state-write.sh の遷移バリデーションがあるため、旧マーカーファイルとの併用は不可。autopilot 開始時に旧マーカーの存在チェックを行い、検出時は警告を出力する。

### R3: session-audit の独立性

session-audit は JSONL 分析であり、マーカーファイルには直接依存しない。ただし autopilot-summary から呼び出されるため、summary のマーカー参照廃止と整合させる必要がある。
