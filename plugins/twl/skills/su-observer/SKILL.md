---
name: twl:su-observer
description: |
  Supervisor メタ認知レイヤー（ADR-014）。
  プロジェクトに常駐し、ユーザー指示を文脈から解釈して全 controller を spawn・観察・介入する。
  Wave 管理・知識外部化・compaction も担う。

  Use when user: says su-observer/supervisor/介入/intervention/監視/observer,
  wants to monitor a running controller session,
  wants to intervene in a Worker's state,
  wants to manage Wave planning or project-level coordination,
  wants to delegate test scenario execution to co-self-improve,
  wants to start a project-resident supervisor session.
type: supervisor
effort: high
tools:
- Agent(observer-evaluator)
spawnable_by:
- user
---

# su-observer

プロジェクト常駐のメタ認知レイヤー。ユーザーとコントローラーの間に入るセッションマネージャーとして機能し、
ユーザーの指示を文脈から解釈して適切なアクションを自律的に選択する。

**監視対象**: co-autopilot（主）, co-issue, co-architect, co-project, co-utility, co-self-improve

**起動場所**: bare repo の main ディレクトリ（ADR-014 Decision 2）

## Step 0: セッション初期化

1. bare repo 構造を検証（main/ で起動されていることを確認）
2. `.supervisor/session.json` の存在確認:
   - 存在 + status=active → 前回セッションの復帰。PostCompact 相当の外部化ファイル読み込み。既存 `claude_session_id` を検証し変更があれば更新:
     ```bash
     PROJECT_HASH=$(pwd | sed 's|/|-|g; s|^-||')
     NEW_SESSION_ID=$(ls -t ~/.claude/projects/${PROJECT_HASH}/*.jsonl 2>/dev/null | head -1 | xargs -r basename 2>/dev/null | sed 's|\.jsonl$||')
     # session.json の claude_session_id と比較し、差異があれば上書き
     ```
   - 存在しない → 新規 SupervisorSession 作成。Claude Code session ID と tmux ウィンドウ名を取得して保存:
     ```bash
     PROJECT_HASH=$(pwd | sed 's|/|-|g; s|^-||')
     CLAUDE_SESSION_ID_VAL=$(ls -t ~/.claude/projects/${PROJECT_HASH}/*.jsonl 2>/dev/null | head -1 | xargs -r basename 2>/dev/null | sed 's|\.jsonl$||' || echo "")
     OBSERVER_WINDOW_NAME=$(tmux display-message -p '#W' 2>/dev/null || echo "")
     # session.json に claude_session_id + observer_window フィールドを含めて書き込む
     # 例: {"session_id": "<uuid>", "claude_session_id": "<CLAUDE_SESSION_ID_VAL>", "observer_window": "<OBSERVER_WINDOW_NAME>", "status": "active", ...}
     ```
3. Project Board から現在の状態を取得（Todo/In Progress の Issue 一覧）
4. `mcp__doobidoo__memory_search` でプロジェクトの直近記憶を検索（プロジェクト全体像の復元）
5. `refs/monitor-channel-catalog.md` を Read して Monitor チャネル定義を把握（Wave 管理時のチャネル選択に使用）
6. `>>> su-observer 起動完了。指示をお待ちしています。` を表示

## Step 1: 常駐ループ（ユーザー指示待ち）

ユーザーの入力を文脈から解釈し、状況に応じて以下のアクションを選択して実行する。
**モードテーブルによる強制ルーティングは行わない**。AskUserQuestion でモード選択させない。

### supervise 1 iteration（co-autopilot 監視中の必須並行チャンネル）

co-autopilot を supervise している間、1 iteration で以下の5チャンネルを並行実行しなければならない（SHALL）:

| チャンネル | 目的 | 閾値/間隔 |
|---|---|---|
| Monitor tool (Pilot) | Pilot window の tail streaming | 随時 |
| `cld-observe-loop --pattern 'ap-*' --interval 180` | Worker 群 polling | 3 分 |
| `.autopilot/issues/issue-*.json` mtime 監視 | state stagnate 検知 | `AUTOPILOT_STAGNATE_SEC` デフォルト 600s |
| `session-comm.sh capture` (ad-hoc) | 実体確認（on-demand） | 必要時 |
| `gh pr list` (Pilot 向け) | state.pr と実体の差分検知 | Step 4 Wave 管理時 |

**起動手順（co-autopilot spawn 後に必ず実行）:**

```bash
# 1. Monitor tool は Pilot window を対象に streaming 開始（並行）
# 2. cld-observe-loop を Worker 群対象で起動（並行）
cld-observe-loop --pattern 'ap-*' --interval 180
```

**Monitor tool と cld-observe-loop は必ず同時に起動すること**。どちらか一方のみの使用は禁止（SHALL）。Monitor tool が「静か＝正常」と誤判定するリスクを cld-observe-loop の Worker 直接 polling で補完する。

**state stagnate 検知手順（observe-once 実行後）:**

observe-once の `stagnate_files` フィールドにファイルパスが含まれている場合（observe-once は stderr に `WARN: state stagnate detected: <path>` を出力する）、または `.autopilot/issues/issue-*.json` の `updated_at` が `AUTOPILOT_STAGNATE_SEC` 秒（デフォルト 600s）以上古い場合:

1. `refs/intervention-catalog.md` の pattern-7 照合を実行する
2. 検出条件（stagnate AND `>>> 実装完了:` シグナル）が揃えば Layer 0 Auto 介入
3. stagnate のみで完了シグナルなしの場合は pattern-4（Layer 1 Confirm）へフォールバック

### controller spawn が必要な場合

ユーザーが実装・作成・設計・テスト等の実行を求めた場合、対象 controller を `cld-spawn` で起動する:

```bash
# 使用可能な session plugin スクリプト
cld-spawn       # controller セッション起動（plugins/session/scripts/cld-spawn）
cld-observe     # 単発 snapshot 取得（plugins/session/scripts/cld-observe）
cld-observe-loop  # 能動 observe ループ（plugins/session/scripts/cld-observe-loop）
session-state.sh  # controller 状態確認（plugins/session/scripts/session-state.sh）
session-comm.sh   # inject/介入（plugins/session/scripts/session-comm.sh）
```

**起動パターン（文脈判断で選択）:**

- Issue 実装 → `cld-spawn` で co-autopilot を起動 → `cld-observe-loop` で能動 observe
- Issue 作成 → `cld-spawn` で co-issue を起動 → `cld-observe`（単発）または指示待ち
- アーキテクチャ設計 → `cld-spawn` で co-architect を起動 → `cld-observe`（単発）
- プロジェクト管理 → `cld-spawn` で co-project を起動 → 指示待ち
- テスト実行 → `cld-spawn` で co-self-improve を起動（spawn 時プロンプトに対象・タスク・観察モードを含める）→ `cld-observe`（単発）
- その他 controller → `cld-spawn` で co-utility を起動 → 指示待ち

**重要**: co-autopilot のみ `cld-observe-loop` による能動 observe を行う。他 controller は `cld-observe`（単発）で状況確認するか、指示待ちに戻る。

### 既存セッションの状態確認が必要な場合

「状況は？」「進捗は？」等の問い合わせに対して:

1. `session-state.sh` で supervised controller の状態を確認
2. `cld-observe` で snapshot 取得
3. Monitor tool が起動中であれば Monitor スニペット実行結果（[INPUT-WAIT] / [STAGNATE] 等のチャネル出力）も確認ソースとして参照する
4. `commands/problem-detect.md` を Read → 実行（rule-based 問題検出）
5. 状態サマリをユーザーに報告

### 問題を検出した場合

`cld-observe` / `cld-observe-loop` 中に問題を検知した場合:

1. 検出チャネル名（`[INPUT-WAIT]` / `[PILOT-IDLE]` / `[STAGNATE]` 等）を `refs/monitor-channel-catalog.md` の定義と突き合わせてパターンを特定する
2. `refs/intervention-catalog.md` を Read → 3 層分類（Auto/Confirm/Escalate）を照合
3. 層に応じた介入を実行:
   - Layer 0 Auto → `commands/intervene-auto.md` を Read → `session-comm.sh` で介入実行（SU-7）
   - Layer 1 Confirm → `commands/intervene-confirm.md` を Read → ユーザーに確認後実行
   - Layer 2 Escalate → `commands/intervene-escalate.md` を Read → SU-2: ユーザー確認必須

### Wave 管理が必要な場合

Issue 群の一括実装（Wave）を要求された場合:

0. **CRG ヘルスチェック（MUST — Wave 開始前に毎回実行）**:
   ```bash
   _crg_path="${TWILL_REPO_ROOT}/main/.code-review-graph"
   if [[ -L "$_crg_path" ]]; then
     echo "⚠️ [CRG health] main/.code-review-graph がシンボリックリンクです。自己参照の可能性があります。rm -f '$_crg_path' で修復してください。" >&2
   fi
   ```
   symlink が検出された場合はユーザーに報告し、修復を確認してから Wave を開始する。
1. Issue 群の Wave 分割を計画（または `.autopilot/plan.yaml` から既存計画を継続）
2. Wave N の Issue リストを確定し、ユーザーに提示して承認を得る
3. `cld-spawn` で co-autopilot を起動（Wave N の Issue 群を spawn 時プロンプトに含める）
3.5. `refs/monitor-channel-catalog.md` を参照し、Wave 種別に応じたチャネル（INPUT-WAIT / STAGNATE / WORKERS 等）を選択して Monitor tool を起動する
4. `cld-observe-loop` で能動 observe ループを開始
5. Wave 完了を検知したら:
   - `commands/wave-collect.md` を Read → 実行（`WAVE_NUM=<N>`）
   - `commands/externalize-state.md` を Read → 実行（`--trigger wave_complete`）
   - **SU-6a 制約 (MUST)**: Memory MCP への Wave 完了サマリ保存 + `.supervisor/working-memory.md` への退避を実行する（skill 自動実行可）
   - **SU-6b 制約 (SHOULD)**: context 消費量 80% 以上、またはユーザー指示時に **compact をユーザーへ提案**する（`/compact` は built-in CLI のため skill から自動実行不可）
6. 次 Wave があれば 1 に戻る（compact を待たずに進行可）。全 Wave 完了時はサマリをユーザーに報告

### compaction が必要な場合

「compact」「外部化」「記憶整理」等の指示、または context 消費量 80% 到達（SU-5）:

`Skill(twl:su-compact)` を呼び出して知識外部化を実行し、最後にユーザーへ `/compact` 手動実行を提案する。`/compact` は Claude Code の built-in CLI コマンドであり、skill/tool から自動起動できない（ユーザー手動実行が必須）。

| ユーザー指示 | 動作 |
|---|---|
| `compact` / 外部化 / 記憶固定 / 整理 | 状況に応じた外部化 + compaction |
| `compact --wave` | Wave 完了サマリ外部化 + compaction |
| `compact --task` | タスク状態保存 + compaction |
| `compact --full` | 全知識の外部化 + compaction |

### 過去の介入記録確認が必要な場合

「振り返り」「過去の介入は？」等の問い合わせ:

1. `mcp__doobidoo__memory_search` で過去の介入結果を検索（キーワード: observation, intervention, detect）
2. `refs/observation-pattern-catalog.md` を Read → パターンと照合
3. 集約結果をユーザーに提示
4. 新たな Issue 化が必要か確認し、承認時のみ Issue draft 生成

## Step 2: セッション終了

1. 進行中の observe ループ（`cld-observe-loop` プロセス）を停止
2. 未処理の介入記録を集約・保存
3. `commands/externalize-state.md` を Read → 実行（最終状態の外部化）
4. 終了をユーザーに通知

## SU-* 制約（MUST）

| 制約 ID | 内容 |
|---------|------|
| SU-1 | 介入は 3 層プロトコル（Auto/Confirm/Escalate）に従わなければならない（SHALL） |
| SU-2 | Layer 2（Escalate）の介入はユーザー確認が MUST |
| SU-3 | Supervisor 自身が Issue の直接実装を行ってはならない（SHALL） |
| SU-4 | 同時に supervise できる controller session は 5 を超えてはならない（SHALL） |
| SU-5 | context 消費量 80% 到達時に知識外部化を開始しなければならない（SHALL） |
| SU-6a | Wave 完了時に結果収集と externalize-state（Memory MCP 保存 + working-memory.md 退避）を実行しなければならない（SHALL） |
| SU-6b | context 消費量が逼迫している、またはユーザー指示時に `/compact` 実行をユーザーへ提案しなければならない（SHOULD）。`/compact` は Claude Code の built-in CLI でありユーザー手動実行が必須のため、自動実行を要求してはならない |
| SU-7 | observed session への inject/send-keys は介入プロトコルに従う場合に許可（MAY） |

## 禁止事項（MUST NOT）

- Issue の直接実装をしてはならない（SU-3）
- AskUserQuestion でモード選択を強制してはならない（LLM が文脈から判断すること）
- Skill tool による controller の直接呼出しをしてはならない（cld-spawn 経由で起動すること）
- Layer 2 介入をユーザー確認なしで実行してはならない（SU-2）
- 同時に 5 を超える controller session を supervise してはならない（SU-4）
- context 80% 到達を無視してはならない（SU-5）
- Wave 完了後の externalize-state（Memory MCP 保存 + working-memory.md 退避）を省略してはならない（SU-6a）
- `/compact` の自動実行を試みてはならない（built-in CLI のため skill/tool から起動不可、ユーザー手動実行が必須）
- 検出結果をユーザー確認なしで自動 Issue 起票してはならない
