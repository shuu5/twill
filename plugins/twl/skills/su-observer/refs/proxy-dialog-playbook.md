# Proxy Dialog Playbook

su-observer が co-issue / co-architect と proxy 対話する際の完全手順。
SKILL.md から移設（元: L351-L510）。

---

## pipe-pane セットアップ（spawn 直後に実行 — MUST）

cld-spawn 実行直後に pipe-pane でセッション出力をファイルに永続化する:
```bash
tmux pipe-pane -t <window> -o "cat >> /tmp/<controller>-<session-id>.log"
```
pipe-pane は capture-pane の scrollback 制限を補完する。Claude Code の応答テキストは tmux scrollback に残りにくいため、pipe-pane log が AskUserQuestion 読み取りの主要手段となる。

---

## spawn プロンプトの文脈包含（MUST）

cld-spawn のプロンプトには **observer 固有文脈のみ**を含めること（`refs/pitfalls-catalog.md §10` 参照）:
1. spawn 元識別（`su-observer から spawn（window: ..., session: ...）`）
2. Issue 番号 / 事前成果物のパスのみ（`.explore/N/summary.md にリンク済`）
3. proxy 対話期待（`AskUserQuestion は observer が pipe-pane log で代理応答`）
4. observer 独自 deep-dive 観点（skill の標準 Phase で気づけない追加観点）
5. Wave 文脈 / 並列タスク境界

**最小 prompt 例（co-issue refine 向け 5-10 行テンプレ）:**
```
su-observer から spawn（window: co-issue-refine-HHMMSS, session: <sess>）

Issue: #<N>（explore summary: .explore/<N>/summary.md にリンク済）
AskUserQuestion は observer が pipe-pane log で代理応答します。

observer 独自観点: <specialist review で検出した具体的懸念点のみ記載。なければ省略>

Wave <W> 並列タスク境界（他 Issue と独立）
```

**MUST NOT: skill 自律取得可能情報の転記**（`refs/pitfalls-catalog.md §10` 参照）。Issue body / labels、explore summary、architecture 文書、SKILL.md の Phase 手順、past memory 生データなどは転記禁止。

---

## proxy 対話ループ

```
1. cld-spawn で controller を起動（上記の文脈をプロンプトに含める）
2. spawn 直後に pipe-pane セットアップ
3. 以下を繰り返す:
   a. session-state.sh state <window> で input-waiting を検知するまで 15-30 秒間隔でポーリング
   b. input-waiting 検知 → pipe-pane log を ANSI strip して質問内容を読む:
      cat /tmp/<log>.log | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -iE "Enter.?to.?select|Esc.?to.?cancel"
      質問内容が見つかったら、その周辺を読んで選択肢を把握する
   c. 質問内容を読めた → ユーザーの文脈と要求に基づいて応答を判断
   d. session-comm.sh inject <window> "<response>" で応答を送信
4. controller が全 Phase を完了して最終結果を出力 → ループ終了
5. キャプチャで最終結果を読み取り、ユーザーに報告
```

---

## キャプチャ内容を読まない inject の禁止（MUST NOT）

input-waiting を検知しても、質問内容を読まずに inject してはならない。
質問内容が読めない場合の段階的フォールバック:
1. pipe-pane log を ANSI strip して検索
2. `tmux capture-pane -t <window> -p -S -500` で scrollback 拡大
3. それでも読めない → ユーザーにエスカレート（SU-2 相当）

「Phase が進んだだろう」という推測で inject することは禁止。

---

## AskUserQuestion の UI パターン

Claude Code の AskUserQuestion は番号付きメニュー形式でレンダリングされる:
```
❯ 1. 選択肢A
   説明テキスト
  2. 選択肢B
   説明テキスト
Enter to select · ↑/↓ to navigate · Esc to cancel
```
inject する応答は **番号**（"1", "2"）またはメニュー項目のテキスト。`[A]/[B]/[C]` 形式ではない。

---

## AskUserQuestion multiSelect UI 操作プロトコル

multiSelect UI（複数選択可）では `session-comm.sh inject` の後に Tab/Enter を明示送信する必要がある:
```bash
# 1. 選択肢を literal 送信（数字 or テキスト）
session-comm.sh inject <window> "1"
# 2. 必要に応じて Tab で質問切替 / Submit 行への移動
tmux send-keys -t <window> Tab
# 3. Enter で最終送信
tmux send-keys -t <window> Enter
```

**操作仕様（MUST）:**
- **Tab**: 質問切替（複数質問時）または Submit 行への移動（単一質問時）
- **↑/↓**: item 移動 + toggle（multiSelect 時）
- **数字 (1-9)**: 直接 toggle
- **Submit 行**: Tab で切替後に Enter で送信
- **MUST**: `session-comm.sh inject` は `-l`（literal）で送るため Tab/Enter 等の特殊キーは解釈されない

**inject 後のキュー残留確認（MUST）:**
```bash
# inject 後に capture-pane で "Press up to edit" を確認。残留なら Enter 送信
tmux capture-pane -t <window> -p -S -3 | grep -q "Press up" && \
    tmux send-keys -t <window> Enter
```

---

## explore フェーズの批判的深堀り（MUST）

co-issue の Phase 1（explore）で observer は批判的な深堀りを行わなければならない:
- summary-gate の前に**最低 1 往復**の explore 対話を実施
- 深堀り内容: 設計の前提を疑う、代替案の提示、影響範囲の確認、コードベース検証
- co-issue が explore 質問を出したら、具体的な回答を inject（「A」で済ませない）

---

## specialist review 必須ガード（MUST）

co-issue の Phase 3（specialist review）は**絶対にスキップしてはならない**:
- **3 specialist 全て必須**: issue-critic, issue-feasibility, worker-codex-reviewer
- refine モードでも新規作成モードでもフローは同一。省略不可
- **refined ラベル = レビュー済み**。specialist review なしで refined を付与してはならない

orchestrator フォールバック時のリカバリ手順:
1. **retry**: orchestrator `--resume` で再実行
2. **手動 specialist spawn**: observer 自身が 3 agent を並列 spawn
3. **ユーザーにエスカレート**: 上記 2 つが失敗した場合

**「accept partial」で specialist review をバイパスすることは禁止（MUST NOT）。**

---

## co-issue refine の proxy 対話例

```
observer → pipe-pane セットアップ
  → cld-spawn co-issue "refine #N ... [observer 固有文脈]"
  → co-issue: Phase 1 探索・分析
  → observer: pipe-pane log で explore 質問を読む → 批判的な具体回答を inject
  → co-issue: さらに探索（1 往復以上）
  → co-issue: summary-gate で番号メニューを表示
  → observer: pipe-pane log で選択肢を読む → "1" を inject
  → co-issue: Phase 2 → dispatch 確認
  → observer: pipe-pane log で確認 → "1" (dispatch) を inject
  → co-issue: Phase 3 specialist review（3 specialist 全実行）
  → co-issue: Phase 4 結果表示
  → observer: pipe-pane log で最終結果を読む → ユーザーに報告
```

---

## observer 独自判断での応答

- summary-gate 修正: observer がコードベース調査に基づき具体的な修正点を inject
- dispatch 調整: 依存関係に問題を発見した場合に調整を inject
- specialist review フォールバック: retry → 手動 spawn の判断を自律実行
- 判断に迷う場合のみユーザーにエスカレート（SU-2 相当）

---

*移設元: su-observer SKILL.md L351-L510（proxy 対話セクション）*
