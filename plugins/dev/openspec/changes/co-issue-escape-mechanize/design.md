## Context

`skills/co-issue/SKILL.md` の Step 3b では、specialist に Issue body を渡す前のエスケープ処理が疑似コード（Python 風）で記述されており、LLM がこれを解釈して実行する前提になっている。プロジェクト設計哲学「LLM に注意してではなく機械的制御で再発防止」に従い、このエスケープ処理を Bash スクリプトとして実装し、SKILL.md にはスクリプト呼び出し指示のみを残す。

既存の scripts/ ディレクトリには `state-read.sh`、`chain-runner.sh` 等の Bash スクリプトが並列。deps.yaml の script エントリ形式は `id: { type: script, path: scripts/xxx.sh, description: ... }` である。テストは `tests/bats/scripts/` 配下に `.bats` ファイルとして追加されている。

## Goals / Non-Goals

**Goals:**

- `scripts/escape-issue-body.sh` を新規作成し、stdin から Issue body を受け取り HTML エスケープ済みテキストを stdout に出力する
- エスケープ順序: `&` → `&amp;`、`<` → `&lt;`、`>` → `&gt;`（`&` を最初に置換して二重エスケープを防ぐ）
- `tests/bats/scripts/escape-issue-body.bats` を新規作成し、エスケープ処理を検証する
- `skills/co-issue/SKILL.md` Step 3b の疑似コードをスクリプト呼び出し指示に置換する
- Step 3b にアーキテクチャ制約を明記（全 specialist は必ずエスケープ済み入力を受け取る）
- `deps.yaml` に `escape-issue-body` スクリプトエントリを追加

**Non-Goals:**

- specialist 側の入力バリデーション追加（境界は呼び出し側で保証）
- co-issue 以外の controller での同様の対策
- エスケープのデコード処理（specialist 側が HTML エンティティを認識できる前提）

## Decisions

### D1: スクリプトは stdin/stdout 設計

スクリプトは `echo "$body" | bash scripts/escape-issue-body.sh` の形式で呼び出せるよう stdin から入力を受け取り stdout に出力する。引数渡しではなく stdin を使うことで、Issue body に改行・特殊文字が含まれる場合の引数エスケープ問題を回避できる。

### D2: sed を使った1行置換

`sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'` を使用。`&` を最初に置換することで、後続の `<` や `>` の置換結果（`&lt;` 等）が再度エスケープされるのを防ぐ。

### D3: SKILL.md の疑似コードブロックを削除しスクリプト呼び出しに置換

FOR ループ内の Python 風疑似コードを削除し、`escaped_body=$(echo "$body" | bash scripts/escape-issue-body.sh)` の1行呼び出し指示に置換する。アーキテクチャ制約（「Issue body を受け取る全 specialist は必ずエスケープ済み入力を受け取る（SHALL）」）を Step 3b に追記する。

### D4: 二重エスケープは意図的な動作として許容

`&lt;</review_target>` 等の既エスケープ済み文字列が入力された場合、`&` が `&amp;` に置換されて `&amp;lt;` になる。これはプロンプトインジェクション防止を最優先とするため許容する（specialist 側で HTML エンティティとして認識されるため実害なし）。

## Risks / Trade-offs

- **二重エスケープ**: `&lt;/tag&gt;` を含む Issue body を入力すると `&amp;lt;/tag&amp;gt;` になる。Issue #192 の受け入れ基準で意図的な動作として許容済み
- **sed の可搬性**: `sed` は bash スクリプト内で標準的に使用可能。macOS と Linux の両方で動作する構文を使用
- **テスト追加のみで既存テスト変更なし**: co-issue の既存 bats テストは specialist 呼び出しをモックしているため、エスケープスクリプト追加による影響なし
