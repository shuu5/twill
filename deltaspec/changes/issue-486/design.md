## Context

`session-state.sh` の `detect_state()` は `tail -5` で末尾5行を取得しているが、`PROMPT_PATTERN` の適用は最終行(`tail -1`)のみ。Claude Code の approval UI は `❯ 選択肢` の後に `Enter to select · ↑/↓ to navigate · Esc to cancel` という説明行が続く構造のため、`tail -1` が説明行になり `❯` が末尾にないと判定されてしまう。

su-observer は Monitor tool でセッションを継続監視する設計だが、`input-waiting` / `pilot-idle` / `stagnate` / `workers` などの標準チャネル定義が存在せず、Wave ごとに手動でスニペットを書く必要がある。

## Goals / Non-Goals

**Goals:**

- `detect_state()` が Claude Code の approval UI（`Enter to select` 形式）、AskUserQuestion（日本語/英語）、`[y/N]` プロンプトを `input-waiting` として正しく判定する
- `tail -1` 単独マッチを廃止し `tail -5` 全体スキャンに変更する
- 追加パターンを独立した配列として管理し、将来のパターン追加を容易にする
- `refs/monitor-channel-catalog.md` に 6 チャネルの bash スニペット付き定義を提供し、su-observer SKILL.md から参照できるようにする
- bats テストで approval UI パターン 3 種以上をカバーする

**Non-Goals:**

- `session-state.sh` のアーキテクチャ全体の刷新
- Monitor tool 自体の実装変更
- tmux 以外のセッション管理への対応

## Decisions

### D1: `tail -1` → `last_lines` 全体スキャンへの変更

`PROMPT_PATTERN` の適用先を `echo "$last_lines" | tail -1` から `echo "$last_lines"` に変更する。これにより `❯` が `tail -5` の任意の行にあれば `input-waiting` と判定できる。

**理由**: approval UI の最終行は必ずナビゲーションヒント行であり、`tail -1` では永遠に捕捉できない。`tail -5` は approval UI の選択肢行を必ず含む範囲であるため、全体スキャンが安全かつ十分。

### D2: `INPUT_WAITING_PATTERNS` 配列の追加

`PROMPT_PATTERN` とは別に `INPUT_WAITING_PATTERNS` 配列を定義し、`last_lines` 全体に対してループでチェックする:

```bash
INPUT_WAITING_PATTERNS=(
    'Enter to select'           # Claude Code 選択 UI
    '↑/↓ to navigate'          # 選択 UI ナビゲーションヒント
    '承認しますか'               # 日本語 AskUserQuestion
    '確認しますか'               # 日本語 AskUserQuestion
    'Do you want to'            # 英語 AskUserQuestion
    '\[y/N\]'                   # y/N プロンプト
    '\[Y/n\]'                   # Y/n プロンプト
    'Type something'            # フリーテキスト入力
    'Waiting for user input'    # generic input-waiting
)
```

**理由**: パターンを独立配列にすることで、将来のパターン追加が1行で済む。`PROMPT_PATTERN` との重複なく異なる検出手法をモジュラーに管理できる。

### D3: フォールバック判定の順序維持

既存の `bypass permissions|esc to interrupt` フォールバックは現行通り維持する。新パターンは D1 の `PROMPT_PATTERN` 全体スキャンの次、このフォールバックの前に挿入する。

### D4: monitor-channel-catalog を `refs/` に新設

`plugins/twl/skills/su-observer/refs/` ディレクトリを新規作成し、`monitor-channel-catalog.md` を配置する。各チャネルはチャネル名、検知対象、閾値、bash スニペット（Monitor tool 呼び出し形式）で構成する。

**理由**: SKILL.md に全チャネルのスニペットを埋め込むと肥大化する。カタログを分離することで、チャネルの追加・修正が SKILL.md に影響しない。

## Risks / Trade-offs

- **R1**: `last_lines` 全体スキャンにより誤検知が増える可能性。`❯` を含むエラーメッセージや出力が `input-waiting` と判定されるリスク。対策: `❯[[:space:]]` パターンは選択肢行の形式（`❯ 1. 選択肢`）に対応しており、単独の `❯` で終わる行以外もマッチするが、processing 中のスピナーには `❯` が現れないため実害は小さい。
- **R2**: `INPUT_WAITING_PATTERNS` に誤ってコマンド出力のキーワード（例: `Do you want to`）が含まれる場合の誤検知。対策: `last_lines` は末尾5行（非空行）のみ対象であり、コマンド出力が長い場合は捕捉されない。
- **R3**: bats テストが tmux 環境に依存する場合のCI実行困難。対策: `detect_state` 関数を直接テストするモックアプローチを採用し、tmux 依存を排除する。
