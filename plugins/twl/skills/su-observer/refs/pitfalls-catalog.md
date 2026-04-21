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
| 3.4 | co-issue / co-architect spawn 後「指示待ち」に戻ってしまう | **proxy 対話ループ必須（SKILL.md L299）** — observer がユーザー代理で対話継続 |
| 3.5 | spawn プロンプトにユーザー文脈が不足、controller が迷子 | 元指示・背景・決定事項・判断基準・deep-dive ポイントを全て prompt に包含（SKILL.md L309-316） |
| 3.6 | co-autopilot は能動 observe（cld-observe-loop）、co-issue / co-architect は proxy 対話 — 混同すると監視漏れ | controller ごとの観察モードを明示判別（SKILL.md L288-295） |

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

## 7. SKILL.md 引用資産の所在（骨抜き回避）

SKILL.md は以下を参照するが、**Phase A 時点で一部未実装**（Phase B で作成予定）:

| 参照 | 実在 | 代替 |
|------|:-:|------|
| `refs/monitor-channel-catalog.md` | 〇 | — |
| `refs/intervention-catalog.md` | ×（Phase B） | SKILL.md L269-272 / L440-449 のインライン定義を参照 |
| `refs/observation-pattern-catalog.md` | ×（Phase B） | doobidoo `observer-pitfall` / `observer-lesson` タグ検索で代替 |
| `refs/pitfalls-catalog.md` | **〇（本ファイル）** | — |
| `commands/intervene-auto.md` | ×（Phase B） | SKILL.md L447 のインライン `session-comm.sh` 手順 |
| `commands/intervene-confirm.md` | ×（Phase B） | 同上、ユーザー確認込み |
| `commands/intervene-escalate.md` | ×（Phase B） | SU-2 に従う（ユーザー確認必須） |
| `commands/wave-collect.md` | ×（Phase B） | SKILL.md L468-500 の Wave 完了インライン手順 |
| `commands/externalize-state.md` | ×（Phase B） | 下記「externalize inline」を実行 |
| `commands/problem-detect.md` | ×（Phase B） | 本カタログと monitor-channel-catalog から手動照合 |
| `scripts/spawn-controller.sh` | **〇（Phase A 新規）** | — |

---

## 8. externalize-state inline 手順（commands/externalize-state.md 代替、Phase A 暫定）

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
