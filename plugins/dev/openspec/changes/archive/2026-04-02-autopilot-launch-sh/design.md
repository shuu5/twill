## Context

autopilot-launch.md は現在 6 ステップの bash コードブロックを LLM が解釈・構築して実行する。他の autopilot 関連コマンド（autopilot-plan.sh, state-write.sh, crash-detect.sh, worktree-create.sh）は全て決定的シェルスクリプトとして実装済み。autopilot-launch だけが .md（LLM 解釈）で残っており、tmux コマンドの構築で非決定的なバグが発生している。

## Goals / Non-Goals

**Goals:**

- autopilot-launch.md の Step 0.5〜3, 5, 6 を `scripts/autopilot-launch.sh` に移行
- フラグ形式の引数で全パラメータを受け取る決定的インターフェース
- bare repo 検出、バリデーション、tmux 起動、クラッシュ検知をスクリプト内で完結
- autopilot-launch.md を Step 4（コンテキスト構築）+ スクリプト呼び出しに簡素化

**Non-Goals:**

- Step 4（コンテキスト注入テキスト構築）のスクリプト化（LLM 判断が必要）
- 既存の state-write.sh / crash-detect.sh のインターフェース変更
- Worker 側の動作変更

## Decisions

### D1: フラグ形式引数

```
autopilot-launch.sh --issue N --project-dir DIR --autopilot-dir DIR \
  [--context TEXT] [--repo-owner OWNER] [--repo-name NAME] [--repo-path PATH]
```

**理由**: positional args は順序依存でエラーの元。フラグ形式なら順序不問で self-documenting。

### D2: SCRIPTS_ROOT の自動解決

`SCRIPTS_ROOT` はスクリプト自身のディレクトリから `$(cd "$(dirname "$0")" && pwd)` で解決。呼び出し元から渡す必要をなくす。

**理由**: 環境変数依存を排除し、スクリプト単体で動作可能にする。

### D3: コンテキストは --context フラグで受け取る

LLM が構築した CONTEXT_TEXT を `--context` フラグで渡す。スクリプト側で `printf '%q'` + `--append-system-prompt` への変換を行う。

**理由**: クォーティング処理をスクリプト内に閉じ込め、LLM がクォートを扱う必要を排除。

### D4: autopilot-launch.md の残存責務

.md は以下のみ担当:
1. CROSS_ISSUE_WARNINGS と PHASE_INSIGHTS から CONTEXT_TEXT を構築
2. `bash $SCRIPTS_ROOT/autopilot-launch.sh` を適切なフラグで呼び出す

**理由**: コンテキスト構築は連想配列の参照や文字列結合が必要で、LLM 判断が介在する。

### D5: 終了コード

| 終了コード | 意味 |
|-----------|------|
| 0 | 成功（Worker 起動完了） |
| 1 | バリデーションエラー（state-write で failed を記録済み） |
| 2 | 外部コマンド不在（cld / tmux） |

## Risks / Trade-offs

- **リスク**: `--context` に改行・特殊文字を含むテキストを渡す際のクォーティング。対策: スクリプト内で `printf '%q'` を使い、呼び出し側は raw テキストを渡すだけにする
- **トレードオフ**: .md と .sh の2ファイルに責務が分散する。しかし LLM 判断部分と決定的処理の分離は設計意図通り
- **リスク**: 既存の autopilot-phase-execute からの呼び出しパスが変更になる。対策: autopilot-launch.md のインターフェース（前提変数）は維持し、内部実装のみ変更
