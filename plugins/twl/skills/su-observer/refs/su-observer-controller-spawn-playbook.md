# controller spawn — 起動パターン・並列度・spawn プロンプト規約

## 起動パターン（文脈判断で選択、spawn-controller.sh 経由）

`cld-spawn` の直接呼び出しは禁止。必ず `${CLAUDE_PLUGIN_ROOT}/skills/su-observer/scripts/spawn-controller.sh` 経由で起動すること（`refs/pitfalls-catalog.md` §1 参照）。

```bash
# Usage:
"${CLAUDE_PLUGIN_ROOT}/skills/su-observer/scripts/spawn-controller.sh" <skill> <prompt-file> [cld-spawn opts...]
```

| controller | 用途 | 並列度（同時 spawn 可能数） | 観察モード |
|---|---|---|---|
| **co-autopilot** | Issue 実装 | **MUST 1 のみ** — 複数 Issue は **1 prompt に列挙**、Pilot が orchestrator 経由で複数 Worker (ap-*) を並列起動する | `cld-observe-loop` で能動 observe |
| **co-explore** | 問題探索 | 複数 spawn 可（各 `.explore/<N>/summary.md` 独立） | **menu 連発型（4-5 menu/session 想定）**: observer は menu 出現 ≤ 60s 以内に応答すべき（SLA）。自律完了型判別: `summary.md` 存在 + menu-ready event なし（single summary, no menu）の場合は自律完了と判定。詳細: `refs/proxy-dialog-playbook.md` 参照 |
| **co-issue** | Issue 作成/refine | 複数 spawn 可（各 `.controller-issue/<sid>/` 独立） | **proxy 対話ループ** |
| **co-architect** | architecture 設計 | 複数 spawn 可だが proxy 負荷重く 1 つずつ推奨 | **proxy 対話ループ** |
| co-project | プロジェクト管理 | 1 推奨 | 指示待ち |
| co-self-improve | テスト実行 | 複数可 | `cld-observe`（単発） |
| co-utility | スタンドアロン | 複数可 | 指示待ち |

使用可能な session plugin スクリプト: `cld-observe`, `cld-observe-loop`, `cld-observe-any`, `session-state.sh`（A5 補助のみ、単独使用禁止）, `session-comm.sh`

## 並列度の核心 — 4 回目を絶対に出さない（ADR-026）

- 「複数 Issue を並列で実行したい」 → **1 Pilot に複数 Issue を列挙して渡す**（Pilot が複数 Worker を並列起動）
- **co-autopilot Pilot を 2 つ spawn してはならない**（`.autopilot/session.json` 競合 = autopilot single-instance 違反）
- 並列単位の階層: co-autopilot Pilot = 常に 1 / orchestrator Worker = MAX_PARALLEL=4 / Issue = 複数同時実行可
- 依存 Issue 群（β → α 等のマージ依存）は 1 Pilot 内 plan の Phase 分割または Wave 分割で順序付ける

## co-autopilot spawn 前 MUST（#1516 — Status=Refined check）

co-autopilot を spawn する**前に必ず**以下を実行すること（`pitfalls-catalog.md §19` 参照）:

1. 対象 Issue の Project Status を確認（`gh project item-list` を使用）:
   ```bash
   gh project item-list <BOARD_NUMBER> --owner <OWNER> --format json \
     | jq -r '.items[] | select(.content.number == <ISSUE_NUM>) | .status'
   ```
2. Status=Todo の場合は `board-status-update --status Refined` を実行:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" board-status-update <ISSUE_NUM>
   ```
3. Status=Refined 確認後に co-autopilot spawn を実行する。

または `spawn-controller.sh co-autopilot` に `--pre-check-issue N` を渡すと自動チェックが走る（AC2）。

## co-autopilot 起動時の推奨経路（#836 — MUST）

`spawn-controller.sh co-autopilot` は **Pilot セッション全体**を spawn する（経路 B）。
Issue 単位の Worker 起動（経路 A: `autopilot-launch.sh`）は Pilot が内部で実行する。observer が `autopilot-launch.sh` を直接呼んで Worker を起動してはならない。

**正規運用（ADR-026 — MUST）:**
- **MUST**: `spawn-controller.sh co-autopilot <prompt>`（`--with-chain` なし）で Pilot を 1 つ spawn する
- **MUST NOT（禁止）**: `--with-chain --issue N` を Issue ごとに叩いてはならない（skill bypass 経路、ADR-026、`refs/pitfalls-catalog.md §13.5`）
- **MUST NOT**: `working-memory.md` 等の前 session コマンドを鵜呑みでコピーしてはならない
- **MUST NOT**: 「co-autopilot と名前が付いているから skill を使っている」と判断してはならない（`--with-chain` 付与で skill bypass が発動）

2 経路の詳細は `co-autopilot SKILL.md §Step 3.5 起動経路比較` および `refs/pitfalls-catalog.md §13` を参照。

## spawn プロンプトの文脈包含規約

spawn prompt は **observer 固有の文脈のみ** を含む（典型 5-15 行、`refs/pitfalls-catalog.md §10` 参照）。

### MUST NOT: skill 自律取得可能情報の転記

以下は skill が自律取得できるため prompt に転記してはならない（MUST NOT）:

- Issue body / labels / title / comments
- explore summary（`twl explore-link read N`）
- architecture 文書（`Read plugins/twl/architecture/vision.md` 等）
- SKILL.md Phase 手順（skill 自身が内包）
- past memory 生データ（`mcp__doobidoo__memory_search`）
- bare repo / worktree 構造（skill が auto-detect）

### MUST: observer 固有文脈のみ（典型 5-15 行）

最小 prompt 例（テンプレート）:
```text
su-observer から spawn（spawn 元識別: window: <win>, session: <id>）
Issue 番号 #<N>: .explore/<N>/summary.md にリンク済
AskUserQuestion は observer が pipe-pane log で代理応答
observer 独自 deep-dive 観点: <観察から得た解釈・優先度付け>
Wave 文脈 / 並列タスク境界: Wave <N>、並列 <M> Issue 中 <K> 番目
```

**例外**: `--force-large` を spawn-controller.sh に渡し、prompt 冒頭に `REASON:` 行で正当化することで 30 行超を許容できる。

## Wave 完遂時の出力規約（#1457）

Pilot (co-autopilot) は Wave 完了時に以下の形式で必ず出力すること（MUST）。これにより `cld-observe-any` の `IDLE_COMPLETED_PHRASE_REGEX` が確実に検知し auto-kill が発火する。

```text
>>> Wave N 完遂: <完了内容の要約>
```

例:
```text
>>> Wave 51 完遂: PR #1234, #1235 マージ完了。次の指示をお待ちします。
```

**注意**: この形式なしに「observer の次の指示を待機」「次の Wave 指示まで休止」等の自然言語表現だけで完了を示すと、`IDLE_COMPLETED_PHRASE_REGEX` が一致しない場合に auto-kill が不発火になる（Issue #1457 pitfall）。`>>> Wave N 完遂:` は machine-readable な completion marker として使うこと。

## Worker 起動時の auto mode 確認方針

Worker pane に `⏵⏵ auto mode on` が出ない場合でも auto mode は有効である（`refs/pitfalls-catalog.md` §4.7-4.8 参照）。確認方法 A（heartbeat ファイル存在確認）/ 確認方法 B（pane capture grep）の詳細は同 §4.7-4.8 を参照。

## 対話型コントローラーとの proxy 対話

co-issue・co-architect は対話的コントローラーであり、observer が spawn した場合は proxy 対話に参加しなければならない（SHALL）。詳細手順は `refs/proxy-dialog-playbook.md` を Read して実行する。

proxy 対話の要点:
- spawn 直後に `tmux pipe-pane -t <window> -o "cat >> /tmp/<ctrl>-<sess>.log"` でセットアップ
- input-waiting 検知 → pipe-pane log を ANSI strip して質問を読む → `session-comm.sh inject` で応答
- co-issue の specialist review は絶対にスキップしてはならない（SHALL）

## spawn 前条件チェック (§11.3) — MUST

**MUST**: controller を spawn する前に必ず `_check_parallel_spawn_eligibility()` を呼び出して並列 spawn 可否を機械判定すること（教訓: `feedback_skill_md_not_enough.md`）。

`spawn-controller.sh` はこのチェックを冒頭で自動実行する。直接 `cld-spawn` を呼び出してはならない（MUST NOT）。

### exit コードと対応アクション

| exit code | 意味 | observer の対応 |
|-----------|------|----------------|
| 0 | 全条件 PASS | ≤ 4 並列で spawn 実行 |
| 1 | precondition 欠落 | ≤ 2 並列に degrade して spawn（stderr の欠落 precondition を確認） |
| 2 | 必須条件欠落 | spawn 完全禁止（stderr の欠落必須条件を確認し、条件充足後に retry） |

### fallback 判断 tree

```
_check_parallel_spawn_eligibility
├── exit 0 → spawn 実行（≤ 4 並列）
├── exit 1 → degrade: 現在の並列数が ≤ 2 になるまで spawn を延期
│             → 欠落 precondition を stderr で確認
│             → 条件充足後に再判定
└── exit 2 → spawn abort
              → 欠落必須条件を stderr で確認
              → Layer 2 Escalate（ユーザー確認）または条件充足後に retry
              → 自律 retry path（将来実装予定、本 Issue は文書化まで）
```

### override（observer 判断による介入時のみ）

```bash
SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="<reason>" spawn-controller.sh <skill> <prompt>
```

`SKIP_PARALLEL_CHECK=1` を設定した場合、`spawn-controller.sh` が自動的に `.supervisor/intervention-log.md` に記録する。理由は `SKIP_PARALLEL_REASON` 環境変数で渡すこと（未指定時は `(reason not provided)` が記録される）。手動上書き記録も許容する。
