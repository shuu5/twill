# su-observer SKILL.md 設計

## 概要

プロジェクト常駐メタ認知レイヤー。main window の cld セッションそのものとして機能し、
ユーザーの指示を文脈から解釈して各 controller を spawn → observe する。

モードテーブルによる強制ルーティングは行わない。LLM が文脈から自然に判断して適切なアクションを選択する。

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

## Step 1: 常駐ループ（行動判断）

ユーザーの入力を文脈から解釈し、以下のガイドラインに従って適切なアクションを選択・実行する。

### 行動判断ガイドライン

**ガイドライン: controller spawn**

ユーザーが実装・作成・設計・テスト等の実行を求めた場合に適用する。
controller の種別は文脈から判断し、`cld-spawn` で起動する。

| 文脈の例 | 適切な controller | observe 方針 |
|---|---|---|
| 「Issue ##を実装して」「Wave を走らせて」 | co-autopilot | `cld-observe-loop`（能動ループ） |
| 「Issue を起票して」「要望を Issue にして」 | co-issue | `cld-observe`（単発）または指示待ち |
| 「アーキテクチャを設計して」 | co-architect | `cld-observe`（単発）または指示待ち |
| 「テストシナリオを実行して」「壁打ちして」 | co-self-improve | `cld-observe`（単発）または指示待ち |
| その他の controller 指定 | co-project / co-utility | 指示待ち |

**ガイドライン: 状態確認**

「状況は？」「進捗は？」「問題ある？」等の問い合わせに対して `session-state.sh` と `cld-observe` を使って状態確認・報告する。

**ガイドライン: 問題検出と介入**

`cld-observe` / `cld-observe-loop` 中に問題を検知した場合、`intervention-catalog` の 3 層分類に従う（SU-1）。
Layer 2（Escalate）は必ずユーザー確認を得ること（SU-2）。

**ガイドライン: Wave 管理**

Issue 群の一括実装（Wave）を要求された場合、Wave 計画 → co-autopilot spawn → observe ループ → wave-collect → externalize-state のフローを実行する（SU-6a）。context 逼迫時またはユーザー指示時に /compact をユーザーへ提案する（SU-6b）。

**ガイドライン: compaction**

「compact」指示または context 80% 到達時（SU-5）に `Skill(twl:su-compact)` を実行する。

**ガイドライン: 過去記録確認**

「振り返り」等の問い合わせに対して doobidoo で過去の介入結果を検索し、結果を報告する。

### session plugin スクリプト

```bash
cld-spawn         # plugins/session/scripts/cld-spawn
cld-observe       # plugins/session/scripts/cld-observe
cld-observe-loop  # plugins/session/scripts/cld-observe-loop
session-state.sh  # plugins/session/scripts/session-state.sh
session-comm.sh   # plugins/session/scripts/session-comm.sh
```

## Step 2: セッション終了

1. observe ループを停止
2. 未処理の介入記録を集約・保存
3. 最終状態の外部化（`commands/externalize-state.md`）
4. 終了をユーザーに通知

## context 自動監視

su-observer は定期的に（または Stop hook で）context 消費量を確認する。
80% 到達時に自動的に Step 1 の「compaction」判断を実行（SU-5 制約）。

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
- AskUserQuestion でモード選択を強制してはならない（LLM が文脈から判断すること）
- Skill tool による controller の直接呼出しをしてはならない（cld-spawn 経由で起動すること）
- Layer 2 介入をユーザー確認なしで実行してはならない（SU-2）
- 同時に 5 を超える controller session を supervise してはならない（SU-4）
- context 80% 到達を無視してはならない（SU-5）
- Wave 完了後の externalize-state を省略してはならない（SU-6a）
- context 逼迫時またはユーザー指示なしに /compact を自動実行してはならない（SU-6b）

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
