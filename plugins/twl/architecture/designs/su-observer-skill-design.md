# su-observer SKILL.md 設計

## 概要

プロジェクト常駐メタ認知レイヤー。main window の cld セッションそのものとして機能し、
ユーザーの指示を受けて各 controller を spawn → observe する。

## Frontmatter

```yaml
---
name: twl:su-observer
description: |
  Supervisor メタ認知レイヤー（ADR-014）。
  プロジェクト常駐セッションとして全 controller を監視・調整・知識外部化する。
  main window の cld セッションそのものが su-observer として機能する。

  Use when user: says su-observer/supervisor/observer/監視/常駐,
  wants to start a project-resident supervisor session,
  wants to manage Waves and autopilot sessions.
type: supervisor
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
---
```

## Step 0: セッション初期化

1. bare repo 構造を検証（main/ で起動されていることを確認）
2. `.supervisor/session.json` の存在確認:
   - 存在 + status=active → 前回セッションの復帰。PostCompact 相当の外部化ファイル読み込み
   - 存在しない → 新規 SupervisorSession 作成
3. Project Board から現在の状態を取得（Todo/In Progress の Issue 一覧）
4. doobidoo でプロジェクトの直近記憶を検索（プロジェクト全体像の復元）
5. `>>> su-observer 起動完了。指示をお待ちしています。` を表示

## Step 1: 指示待ちループ（常駐）

ユーザー入力を解析し、以下のモードに振り分ける:

| モード | 判定条件 | 動作 |
|---|---|---|
| autopilot | autopilot / 実装 / Wave / Issue 番号群 | Step 2 へ |
| issue | issue / Issue作成 / 要望 | Step 3 へ |
| architect | architect / 設計 / アーキテクチャ | Step 4 へ |
| observe | observe / 監視 / チェック / 状態確認 | Step 5 へ |
| compact | compact / 外部化 / 記憶固定 / 整理 | Step 6 へ |
| delegate | その他の controller 名指定（co-utility, co-project 等） | Step 7 へ |

## Step 2: autopilot モード — Wave 管理 + co-autopilot spawn

1. Issue 群の Wave 分割を計画（または既存の Wave 計画を継続）
2. Wave N の Issue リストを確定
3. `session:spawn` で co-autopilot を起動:
   ```
   /session:spawn co-autopilot --issues <issue_list> --wave <N>
   ```
4. observe ループ開始（Step 5 の observe を定期実行）
5. Wave 完了検知 → 結果収集（wave-collect atomic）
6. su-compact 実行（Step 6）
7. 次 Wave があれば Step 2-2 に戻る
8. 全 Wave 完了 → サマリ報告

## Step 3: issue モード — co-issue spawn

1. ユーザーの要望を整理
2. `session:spawn` で co-issue を起動
3. co-issue の完了を observe
4. 結果をユーザーに報告

## Step 4: architect モード — co-architect spawn

1. 設計テーマを確認
2. `session:spawn` で co-architect を起動
3. co-architect の完了を observe
4. 結果をユーザーに報告

## Step 5: observe モード — controller 状態確認

1. `tmux list-windows` で全 window 一覧取得
2. supervised controller の状態を確認（session-state.sh + capture）
3. 問題検出:
   - rule-based: `problem-detect` atomic
   - LLM: `observer-evaluator` specialist（rule-based で検出なしの場合）
4. 問題あり → `intervention-catalog` 参照 → Auto/Confirm/Escalate 実行
5. 問題なし → 状態サマリをユーザーに報告

## Step 6: compact モード — 知識外部化 + compaction

`su-compact` workflow を実行する。

### su-compact の概要

1. **状況判定**: 現在のコンテキストを分析し外部化戦略を決定
2. **外部化実行**:
   - タスク途中 → `.supervisor/task-state.md` に構造化書き出し
   - Wave 完了後 → doobidoo にサマリ保存 + `.supervisor/wave-{N}-summary.md`
   - 設計議論後 → ADR / architecture ファイルへの反映確認
   - 障害対応後 → `.supervisor/intervention-log.md` に追記
3. **compaction 実行**: `/compact` を実行
4. **PostCompact**: 外部化ファイルの再読み込みリスト表示

### ユーザー指示のバリエーション

- `compact` → 自動判定で外部化 + compaction
- `compact --wave` → Wave 完了サマリ外部化 + compaction
- `compact --task` → タスク状態保存 + compaction
- `compact --full` → 全知識の外部化 + compaction

## Step 7: delegate モード — 任意 controller spawn

1. 指定された controller を `session:spawn` で起動
2. observe ループ開始
3. 完了を報告

## context 自動監視

su-observer は定期的に（または Stop hook で）context 消費量を確認する。
50% 到達時に自動的に Step 6 を提案（SU-5 制約）。

## PreCompact / PostCompact Hook 設計

### PreCompact hook（su-precompact スクリプト）

```bash
#!/bin/bash
# .claude/settings.json の PreCompact hook から呼ばれる
# 実行環境: main ディレクトリ

SUPERVISOR_DIR=".supervisor"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

# 現在の外部化ファイルリストを書き出し
echo "PreCompact: $TIMESTAMP" >> "$SUPERVISOR_DIR/compaction-log.txt"
```

### PostCompact hook（su-postcompact スクリプト）

```bash
#!/bin/bash
# .claude/settings.json の PostCompact hook から呼ばれる
# 外部化されたファイルのパスリストを stdout に出力し、
# Claude Code に再読み込みを促す

SUPERVISOR_DIR=".supervisor"

if [ -f "$SUPERVISOR_DIR/task-state.md" ]; then
  echo "[PostCompact] 復帰ファイル: $SUPERVISOR_DIR/task-state.md"
  cat "$SUPERVISOR_DIR/task-state.md"
fi
```

## 禁止事項（MUST NOT）

- Issue の直接実装をしてはならない（SU-3）
- Layer 2 介入をユーザー確認なしで実行してはならない（SU-2）
- 同時に 5 を超える controller session を supervise してはならない（SU-4）
- context 50% 到達を無視してはならない（SU-5）
- Wave 完了後の su-compact を省略してはならない（SU-6）

## .supervisor/ ディレクトリ構造

```
.supervisor/
├── session.json            # SupervisorSession 状態
├── task-state.md           # 外部化: 現在のタスク状態
├── wave-{N}-summary.md     # 外部化: Wave 完了サマリ
├── intervention-log.md     # 介入記録の集約
├── compaction-log.txt      # compaction 履歴
└── interventions/          # per-intervention JSON（既存継承）
    └── YYYYMMDD-HHMMSS-<pattern-id>.json
```
