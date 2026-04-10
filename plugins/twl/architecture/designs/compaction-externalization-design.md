# Compaction 知的外部化 設計書

## 概要

compaction は単なるコンテキスト圧縮ではなく、**知識の選択的外部化**として設計する。
Claude Code の PreCompact / PostCompact / SessionStart(compact) hook を使い分け、
su-observer の三層記憶モデルを実現する。

---

## 三層記憶モデル — 精密定義

### 3 層の本質的な違い

3 層は **固定性（sharpness）** と **持続性（persistence）** の 2 軸で分類される:

| 層 | 固定性 | 持続性 | 変容パターン |
|----|--------|--------|-------------|
| **Long-term Memory** | sharp/fixed | 永続 | 書き込み後は変化しない。削除するまで残る |
| **Working Memory Externalization** | sharp/fixed | 一時的 | 書き込み後は変化しない。復帰後に破棄 |
| **Compressed Memory** | **dynamic/fuzzy** | セッション内 | compaction のたびに書き換わる。過去の記憶がうっすら残る場合も消える場合もある |

**重要**: Long-term Memory と Working Memory Externalization はどちらも **sharp（明確で固定された記憶）** だが、
持続性が全く異なる（永続 vs 一時的）。
Compressed Memory だけが **dynamic** であり、compaction ごとに変容する「ぼんやりした全体像」。

### Layer 1: Long-term Memory（永続・sharp）

プロジェクトをまたいで残る固定化された知識。

| 保存先 | 用途 | 検索方法 |
|--------|------|----------|
| Memory MCP (pluggable) | セッション横断的な知見、パターン、教訓 | MCP search API |
| auto-memory (`~/.claude/projects/*/memory/`) | プロジェクトメタ情報 | MEMORY.md index → Read |

**Pluggable MCP**: 現在は doobidoo MCP を使用するが、将来の MCP 入れ替えに備えて
su-observer は MCP 名を直接ハードコードせず、設定（reference ファイル等）から参照する。

**書き込みタイミング**:
- su-compact 実行時（ユーザー指示 or Wave 完了時 or 50% 閾値到達時）
- セッション終了前

**特性**: 一度書いたら変わらない。不正確なら削除して書き直す。

### Layer 2: Working Memory Externalization（一時的・sharp）

compaction を安全に通過するための **一時退避領域**。

**ライフサイクル**:
1. PreCompact 時に su-observer が現在の作業状態をファイルに書き出す
2. Compaction が実行される
3. PostCompact 時にファイルを読み込んで context に復元
4. 復元成功後にファイルを消費済みマーク（or 削除）

**保存先**: `.supervisor/working-memory.md`

**特性**: sharp で固定的な記憶だが、compaction 1 回分の寿命しかない。
正しく読み込めたら役割を終える。

### Layer 3: Compressed Memory（中期・dynamic）

Claude Code の compaction が生成する圧縮コンテキスト。

**特性**:
- compaction のたびに **動的に書き換わる**
- 過去の記憶がうっすら記述に残る場合もあれば、消える場合もある
- Working Memory や Long-term Memory のように明確で固定された記憶ではなく、「ぼんやりした全体像」
- Long-term Memory が存在するかもしれない、という **手がかり** になりうる

**su-observer から見た Compressed Memory の役割**:
- 直接制御はできない（Claude Code 内部の処理）
- ただし **PreCompact hook の stdout** が compaction 対象に含まれるため、
  圧縮アルゴリズムに「何を残すべきか」のヒントを渡すことは可能
- SessionStart(compact) で ambient hints を注入することで、
  Compressed Memory の「手がかり」機能を補強できる

---

## Hook 設計 — 3 つの hook の使い分け

### hook 発火順序

```
[Working Memory: context が限界に近づく]
    ↓
① PreCompact hook 発火
    stdout → compaction される context に追加（= 圧縮対象）
    side effect → ファイルへの書き出し
    ↓
② Compaction 実行
    context が圧縮される → Compressed Memory 生成
    ↓
③ PostCompact hook 発火
    stdout → 圧縮後の新 context に注入（= sharp な復帰情報）
    ↓
④ SessionStart(matcher: "compact") hook 発火
    stdout → 新 context に注入（= ambient hints）
```

### 各 hook の役割分担

| Hook | 役割 | stdout の行き先 | 主な用途 |
|------|------|----------------|----------|
| **PreCompact** | Working Memory → ファイルに退避 | compaction **される** context | ①ファイル書き出し（side effect）②圧縮に残すべき情報のヒント |
| **PostCompact** | ファイル → Working Memory 復帰 | compaction **後の** 新 context | sharp な作業状態の復元 |
| **SessionStart(compact)** | ambient hints 注入 | compaction **後の** 新 context | Long-term Memory の存在ヒント、プロジェクト状態概要 |

### なぜ PostCompact と SessionStart(compact) を両方使うか

- **PostCompact**: 作業途中の sharp な情報を復元する（今何をしていたか、次のステップは何か）
- **SessionStart(compact)**: より ambient な情報を提供する（プロジェクト全体の状態、Long-term Memory へのポインタ、監視中の controller 一覧）

PostCompact は「直前の作業の復帰」、SessionStart(compact) は「プロジェクト全体の再認識」と棲み分ける。

---

## Hook 実装

### settings.json 設定

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash plugins/twl/scripts/su-precompact.sh",
            "timeout": 10000
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash plugins/twl/scripts/su-postcompact.sh",
            "timeout": 10000
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash plugins/twl/scripts/su-session-compact.sh",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
```

### su-precompact.sh — Working Memory 退避 + 圧縮ヒント

```bash
#!/bin/bash
# PreCompact hook
# 役割:
#   1. side effect: 現在の作業状態を .supervisor/working-memory.md に書き出す
#   2. stdout: 圧縮に残すべき情報のヒントを出力（Compressed Memory の品質向上）

SUPERVISOR_DIR=".supervisor"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
WM_FILE="$SUPERVISOR_DIR/working-memory.md"

# su-observer が起動していない場合は何もしない
if [ ! -d "$SUPERVISOR_DIR" ]; then
  exit 0
fi

# --- side effect: 作業状態をファイルに退避 ---
# 注: su-observer の SKILL.md が事前に書き出している場合はスキップ
if [ ! -f "$WM_FILE" ] || [ "$(find "$WM_FILE" -mmin +5 2>/dev/null)" ]; then
  # 5分以上古い場合は session.json から最低限の状態を書き出す
  if [ -f "$SUPERVISOR_DIR/session.json" ]; then
    echo "---" > "$WM_FILE"
    echo "externalized_at: \"$TIMESTAMP\"" >> "$WM_FILE"
    echo "trigger: auto_precompact" >> "$WM_FILE"
    echo "---" >> "$WM_FILE"
    echo "" >> "$WM_FILE"
    echo "## Session State (auto-saved by PreCompact)" >> "$WM_FILE"
    echo "" >> "$WM_FILE"
    cat "$SUPERVISOR_DIR/session.json" >> "$WM_FILE"
  fi
fi

echo "$TIMESTAMP pre-compact" >> "$SUPERVISOR_DIR/compaction-log.txt"

# --- stdout: 圧縮ヒント ---
# この出力は compaction される context に含まれるため、
# 圧縮アルゴリズムが「何を残すべきか」を判断するヒントになる
echo "[PreCompact] su-observer 状態が .supervisor/working-memory.md に退避されました"
echo "[PreCompact] PostCompact で復元されます"
```

### su-postcompact.sh — Working Memory 復帰（sharp 情報）

```bash
#!/bin/bash
# PostCompact hook
# 役割: 退避した Working Memory をコンテキストに復元する
# stdout は compaction 後の新 context に直接注入される

SUPERVISOR_DIR=".supervisor"
WM_FILE="$SUPERVISOR_DIR/working-memory.md"

if [ ! -d "$SUPERVISOR_DIR" ]; then
  exit 0
fi

echo "=== [PostCompact] Working Memory 復帰 ==="

# Working Memory の復元（sharp/fixed な作業状態）
if [ -f "$WM_FILE" ]; then
  echo ""
  echo "--- 退避された作業状態 ---"
  cat "$WM_FILE"
  echo ""
  echo "--- 作業状態ここまで ---"
  echo ""
  # 消費済みマーク（次回 compaction で上書きされるため削除は不要）
  mv "$WM_FILE" "$SUPERVISOR_DIR/working-memory.consumed.md" 2>/dev/null
else
  echo "[PostCompact] 退避された Working Memory なし"
fi

# Wave サマリ（直近のもののみ復元）
LATEST_WAVE=$(ls -t "$SUPERVISOR_DIR"/wave-*-summary.md 2>/dev/null | head -1)
if [ -n "$LATEST_WAVE" ]; then
  echo ""
  echo "--- 直近 Wave サマリ ---"
  cat "$LATEST_WAVE"
fi

echo ""
echo "=== [PostCompact] 復帰完了 ==="
```

### su-session-compact.sh — Ambient Hints（fuzzy 情報）

```bash
#!/bin/bash
# SessionStart(compact) hook
# 役割: Compressed Memory を補強する ambient hints を注入する
# Long-term Memory の存在ポインタ、プロジェクト全体の状態概要
# PostCompact の sharp 復帰とは異なり、こちらは「ぼんやりした全体像」を提供

SUPERVISOR_DIR=".supervisor"

if [ ! -d "$SUPERVISOR_DIR" ]; then
  exit 0
fi

echo "=== [SessionStart:compact] su-observer Ambient Context ==="

# プロジェクト全体の状態（ambient）
if [ -f "$SUPERVISOR_DIR/session.json" ]; then
  echo ""
  echo "[Supervisor] アクティブな SupervisorSession が存在します"
  echo "[Supervisor] 詳細は .supervisor/session.json を Read してください"
fi

# Long-term Memory へのポインタ
echo ""
echo "[Long-term Memory] Memory MCP にプロジェクト知見が保存されている可能性があります"
echo "[Long-term Memory] 必要に応じて memory_search で検索してください"

# 介入ログの存在
if [ -f "$SUPERVISOR_DIR/intervention-log.md" ]; then
  INTERVENTION_COUNT=$(wc -l < "$SUPERVISOR_DIR/intervention-log.md" 2>/dev/null || echo 0)
  echo "[Intervention] 介入記録あり（$INTERVENTION_COUNT 行）"
fi

# 外部化ファイル一覧（存在のみ通知、内容は読まない）
echo ""
echo "[外部化ファイル]"
for f in "$SUPERVISOR_DIR"/*.md; do
  [ -f "$f" ] && echo "  - $(basename "$f")"
done 2>/dev/null

echo ""
echo "=== [SessionStart:compact] Ambient Context ここまで ==="
```

---

## 三層記憶の流れ — compaction サイクル

```
                          ┌─────────────────────────┐
                          │   Context Window         │
                          │   (Working Memory)       │
                          │                          │
                          │  ┌─ sharp な作業状態 ─┐  │
                          │  │ 今のタスク、進捗、  │  │
                          │  │ 監視中controller   │  │
                          │  └──────────────────┘  │
                          │                          │
    context 50% 到達      │  ┌─ PreCompact ─────┐   │
    or ユーザー指示       │  │ stdout: 圧縮ヒント  │   │
    ──────────────────→  │  │ file: WM退避       │   │
                          │  └────────────────┘   │
                          └──────────┬──────────────┘
                                     │ Compaction
                                     ▼
                          ┌─────────────────────────┐
                          │   Compressed Memory      │
                          │   (dynamic/fuzzy)        │
                          │                          │
                          │  過去の記憶がうっすら     │
                          │  残ったり消えたり        │
                          │  → Long-term Memoryの     │
                          │    手がかりになりうる     │
                          └──────────┬──────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
          ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
          │ PostCompact   │ │ SessionStart │ │ Long-term    │
          │ (sharp復帰)   │ │ (compact)    │ │ Memory       │
          │               │ │ (ambient)    │ │ (永続)       │
          │ WMファイルの   │ │ プロジェクト  │ │ Memory MCP   │
          │ 内容をcontext │ │ 全体のhints  │ │ で検索可能   │
          │ に注入        │ │ を注入       │ │              │
          └──────────────┘ └──────────────┘ └──────────────┘
               ↓                 ↓                ↓
          ┌─────────────────────────────────────────────┐
          │   新しい Context Window                      │
          │                                              │
          │  Compressed Memory（fuzzy、手がかり）         │
          │  + PostCompact 出力（sharp、作業状態復帰）     │
          │  + SessionStart(compact) 出力（ambient hints）│
          │                                              │
          │  → 必要に応じて Long-term Memory を検索       │
          └─────────────────────────────────────────────┘
```

---

## Memory MCP の Pluggable 設計

Long-term Memory の MCP は入れ替え可能にする。

### 設定ファイル（reference）

`refs/memory-mcp-config.md` に以下を定義:

```yaml
memory_mcp:
  current: doobidoo
  search_tool: mcp__doobidoo__memory_search
  store_tool: mcp__doobidoo__memory_store
  quality_tool: mcp__doobidoo__memory_quality
  search_defaults:
    mode: hybrid
    quality_boost: 0.3
    limit: 5
```

su-observer はこの reference を参照して MCP を呼び出す。
MCP を入れ替える場合はこの reference のみを更新する。

---

## 外部化ファイルスキーマ

### working-memory.md（PreCompact → PostCompact の一時退避）

```markdown
---
externalized_at: "2026-04-10T12:00:00Z"
trigger: auto_precompact | manual | wave_complete
lifecycle: temporary  # PostCompact で消費後に破棄
---

## 現在のタスク

- [ ] タスク1の説明
- [x] タスク2の説明

## 進捗

現在の作業: ...
次のステップ: ...

## 監視中の Controller

| Controller | Window | Status | 最終確認 |
|---|---|---|---|

## 重要なコンテキスト

（compaction で失われると困る sharp な情報をここに記載）
```

### wave-{N}-summary.md（Wave 完了時 → Long-term 保存候補）

```markdown
---
externalized_at: "2026-04-10T12:00:00Z"
trigger: wave_complete
wave_number: 1
lifecycle: persistent  # Long-term Memory にも保存される
---

## Wave 1 サマリ

### 実装結果
| Issue | PR | 結果 | 介入 |
|---|---|---|---|

### 知見
（Long-term Memory に保存すべき教訓）

### 次 Wave への引き継ぎ
（Working Memory に復帰させるべき情報）
```

---

## su-compact スキル/コマンド設計

### 呼び出し方法

```
/su-compact              # 自動判定で外部化 + compaction
/su-compact --wave       # Wave 完了サマリ + compaction
/su-compact --task       # タスク状態保存 + compaction
/su-compact --full       # 全知識の外部化 + compaction
```

### su-compact の処理フロー

1. **外部化先の決定**:
   - 何を Working Memory Externalization（一時退避）に書くか
   - 何を Long-term Memory（永続保存）に書くか
   - 判定基準: 「この compaction を超えてもう使わないが将来必要」→ Long-term、「次のステップで即座に必要」→ Working Memory

2. **Long-term Memory への保存**:
   - Memory MCP に重要知見を保存（refs/memory-mcp-config.md 参照）
   - Wave サマリ、介入パターン、教訓を永続化
   - 保存した hash を記録

3. **Working Memory の退避**:
   - `.supervisor/working-memory.md` に現在の作業状態を書き出し
   - タスク状態、進捗、次のステップ、監視中 controller

4. **compaction 実行**:
   - `/compact` コマンドを実行
   - PreCompact hook: 退避確認 + 圧縮ヒント出力
   - Compaction: Compressed Memory 生成（dynamic/fuzzy）
   - PostCompact hook: Working Memory 復帰（sharp）
   - SessionStart(compact) hook: ambient hints 注入

5. **復帰確認**:
   - PostCompact 出力で作業状態が復帰されたか確認
   - 必要に応じて Long-term Memory を検索して補完

---

## Worker の compaction との差別化

| 観点 | Worker（chain-driven） | su-observer |
|------|----------------------|-------------|
| Long-term Memory 使用 | 原則なし（chain 内完結） | 積極的（Wave サマリ、教訓を永続化） |
| Working Memory 退避 | chain state ファイルが自動的に担う | su-observer が自律的に判断して書き出す |
| Compressed Memory | chain の step 名が残りやすい | プロジェクト全体のぼんやりした全体像 |
| 外部化判断 | **テンプレート化**（chain が決める） | **自律的判断**（状況に応じて戦略を選択） |
| PostCompact 復帰 | chain state → 次の step を再開 | working-memory.md → 作業状態復帰 |
| SessionStart(compact) | 使わない（chain が管理） | ambient hints でプロジェクト全体像を補強 |
