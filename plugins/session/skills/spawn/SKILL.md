---
name: spawn
description: |
  新規セッションで指定プロンプトを実行。コンテキスト引き継ぎなし。
  tmux new-window で cld を起動し、引数をプロンプトとして渡す。

  Use when user wants to: spawn new session, run background task,
  start independent session, run command in new window,
  says 「spawn」「新しいセッション」「バックグラウンドで」
  says 「別ディレクトリで」「コンテキスト付きで」「監視して」
---

# Spawn Skill

新しい tmux ウィンドウで cld を起動し、指定プロンプトを初期入力として実行する。
会話コンテキストは引き継がない（`/fork` との違い）。

## Dynamic Context Injection

!`ls -d ~/projects/local-projects/*/main 2>/dev/null`

## 意図推定（NLU）

ユーザー入力から以下を推定する:

| 意図 | 検出パターン例 | 動作 |
|------|--------------|------|
| 即実行 | 引数なし | カレントディレクトリで `cld-spawn` を即座に実行 |
| cd | 「tradingで」「別ディレクトリで」「paperプロジェクトで」 | AskUserQuestion でプロジェクト選択 |
| prompt | cd 意図なしのテキスト | `cld-spawn "$PROMPT"` を即実行 |

## 実行手順

1. tmux内か確認（tmux外はエラー終了）

2. 意図を推定する

   ### パターン A: 引数なし → 即起動
   `cld-spawn` をカレントディレクトリで実行。

   ### パターン B: cd 意図あり → プロジェクト選択

   DCI で取得したプロジェクト一覧から AskUserQuestion で選択:

   ```
   どのプロジェクトで起動しますか？
   （DCI 一覧からプロジェクト名を選択肢として提示）
   ```

   プロジェクト選択後、追加オプションを multiSelect で提示:

   ```
   追加オプション:
   □ コンテキスト注入（現在の会話の要約を引き継ぐ）
   □ 完了監視（完了時に報告）
   ```

   - コンテキスト注入 → 会話要約を生成して PROMPT に結合（50行以内）
   - 完了監視 → WITH_WATCH=true

   ### パターン C: cd 意図なし・テキストあり → 即実行
   テキストを prompt として `cld-spawn "$PROMPT"` を実行。

3. cld-spawn を実行する

   ```bash
   SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"

   # cd ありの場合
   bash "$SCRIPT_DIR/cld-spawn" --cd "$TARGET_DIR" "$FULL_PROMPT"

   # cd なしの場合
   bash "$SCRIPT_DIR/cld-spawn" "$FULL_PROMPT"
   ```

   cld-spawn の stdout からウィンドウ名を取得（`spawned → tmux window 'WINDOW_NAME'` の形式）。

4. watch 処理（WITH_WATCH=true の場合）

   spawn 後に Bash tool (run_in_background) で監視を開始:

   ```bash
   SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
   WINDOW_NAME="<Step 3で取得したウィンドウ名>"
   bash "$SCRIPT_DIR/session-state.sh" wait "$WINDOW_NAME" input-waiting --timeout 300 && \
     bash "$SCRIPT_DIR/session-comm.sh" capture "$WINDOW_NAME" --lines 30
   ```

   - 完了通知を受け取ったら、capture 結果を要約してユーザーに報告
   - タイムアウト時は「タイムアウトしました（5分）」と報告

## コンテキスト注入の形式

```markdown
# Context from previous session

## 決定事項
- （設計判断、技術選定など）

## 技術制約
- （プロジェクト固有の制約、禁止事項など）

## 関連ファイル
- （議論で参照されたファイルパス）

## 補足
- （その他の重要なコンテキスト）
```

## 注意

- tmux 外では使用不可（エラー終了）
- 会話コンテキストは引き継がれない（コンテキスト注入時はテキスト要約のみ）
- cd なしの場合、作業ディレクトリは呼び出し元の `pwd` が引き継がれる
- セッションスコープの権限は引き継がれない
- watch のタイムアウトはデフォルト300秒（5分）
