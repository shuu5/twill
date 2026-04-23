---
type: workflow
user-invocable: true
spawnable_by: [controller, user]
can_spawn: [composite, atomic, specialist]
tools: [Bash, Skill, Read, Write]
effort: medium
maxTurns: 60
---
# workflow-issue-lifecycle

co-issue v2 Worker runtime。1 issue につき structure → spec-review → aggregate → fix loop → arch-drift → create の全 lifecycle を自律実行する。

## 引数

位置引数 1 つ（per-issue dir の絶対パス）:

```
/twl:workflow-issue-lifecycle <abs-per-issue-dir>
```

## 入力ファイル構造

```
<abs-per-issue-dir>/
  IN/
    draft.md          # issue 本文ドラフト（必須）
    arch-context.md   # architecture コンテキスト（任意）
    policies.json     # ポリシー設定（必須）
    deps.json         # 依存情報（任意）
  STATE               # 現在状態ファイル（workflow が上書き）
  rounds/             # ラウンドごとの成果物
  OUT/
    report.json       # 最終出力
```

## policies.json スキーマ

```json
{
  "max_rounds": 3,
  "specialists": ["worker-codex-reviewer", "issue-critic", "issue-feasibility"],
  "depth": "normal",
  "quick_flag": false,
  "scope_direct_flag": false,
  "labels_hint": ["enhancement"],
  "target_repo": null,
  "parent_refs_resolved": {}
}
```

## 処理フロー（MUST — 全ステップを順に実行）

### Step 0: N=1 不変量ガード

```bash
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null || echo "${CLAUDE_PLUGIN_ROOT:-}")"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-review-session-init.sh" 1
```

### Step 1: 入力読み込み

`$1` = per-issue dir の絶対パスとして受け取る。

```bash
PER_ISSUE_DIR="$1"
# パス検証
if [[ -z "$PER_ISSUE_DIR" || "$PER_ISSUE_DIR" != /* ]]; then
  echo "ERROR: per-issue dir は絶対パスで指定してください" >&2
  exit 1
fi
if [[ "$PER_ISSUE_DIR" =~ /\.\./ || "$PER_ISSUE_DIR" =~ /\.\.$ ]]; then
  echo "ERROR: パストラバーサルは使用できません" >&2
  exit 1
fi
```

以下ファイルを読み込む:
- `$PER_ISSUE_DIR/IN/draft.md` → issue body として使用
- `$PER_ISSUE_DIR/IN/arch-context.md` → architecture コンテキスト（存在しない場合は空文字）
- `$PER_ISSUE_DIR/IN/policies.json` → max_rounds, specialists, depth, target_repo 等
- `$PER_ISSUE_DIR/IN/deps.json` → 依存情報（存在しない場合は空）

### Step 2: STATE 初期化

```bash
printf 'running\n' > "$PER_ISSUE_DIR/STATE"
mkdir -p "$PER_ISSUE_DIR/rounds" "$PER_ISSUE_DIR/OUT"
```

### Step 3: issue-structure

`/twl:issue-structure` を Skill tool で呼び出し、draft.md を構造化する:
- 入力: draft.md の内容
- 出力: 構造化された body（rounds/0/body.md に書き込む）

```bash
mkdir -p "$PER_ISSUE_DIR/rounds/0"
# Skill /twl:issue-structure で body を構造化
# 結果を rounds/0/body.md に書き込む
```

### Step 4: round loop

`round=0` から `policies.max_rounds` まで以下を繰り返す:

```
round = round + 1
STATE ← reviewing
```

#### 4a: spec-review 実行

```bash
printf 'reviewing\n' > "$PER_ISSUE_DIR/STATE"
mkdir -p "$PER_ISSUE_DIR/rounds/${round}"
```

`/twl:issue-spec-review` を Skill tool で呼び出す:
- `specialists`: policies.specialists（デフォルト: worker-codex-reviewer, issue-critic, issue-feasibility）
- `depth`: policies.depth（デフォルト: normal）
- 結果を `rounds/<round>/findings.yaml` に書き込む

**4a 完了後、中断せず直ちに 4b を実行すること（MUST — AskUserQuestion 禁止）。**

#### 4b: aggregate

`/twl:issue-review-aggregate` を Skill tool で呼び出す:
- 入力: findings.yaml の内容
- 結果を `rounds/<round>/aggregate.yaml` に書き込む

**4b 完了後、中断せず直ちに 4c を実行すること（MUST）。**

#### 4c: codex gate

aggregate の codex.status を確認:
- `PASS` でない場合:
  - round == 1 のとき: codex を 1 回再試行
  - それ以外: STATE ← failed → `OUT/report.json` に `status: codex_unreliable` を書き込み → exit 0

#### 4d: findings 判定

aggregate の findings を確認:
- **CRITICAL findings あり** (confidence >= 80, target = issue_description):
  ```bash
  printf 'fixing\n' > "$PER_ISSUE_DIR/STATE"
  ```
  body を修正して `rounds/<round>/body-fixed.md` に書き込み → loop 継続

- **WARNING only**:
  ```bash
  printf 'fixing\n' > "$PER_ISSUE_DIR/STATE"
  ```
  body を修正して `rounds/<round>/body-fixed.md` に書き込み → **break**（ループ終了）

- **clean（findings なし）**: **break**（ループ終了）

#### 4e: max_rounds 到達チェック

```
if round == policies.max_rounds and CRITICAL findings あり:
  STATE ← circuit_broken
  OUT/report.json に { status: circuit_broken, rounds, last_aggregate } を書き込む
  exit 0
```

### Step 4.5: refined ラベル判定

round loop が正常完了した場合（STATE が `circuit_broken` でない場合）、`labels_hint` に `"refined"` を追加する:

```
if STATE != circuit_broken:
  policies.labels_hint ← policies.labels_hint + ["refined"]
```

- `STATE == circuit_broken` の場合: スキップ（round loop が正常完了していないため）
- `STATE == failed` の場合: Step 4c の `exit 0` で制御フローが終了するため Step 4.5 に到達しない（条件式の対象外）

### Step 5: arch-drift

`/twl:issue-arch-drift` を Skill tool で呼び出す:
- 入力: 最終 body（最後の body-fixed.md または rounds/0/body.md）

### Step 6: issue 作成

`/twl:issue-create` を Skill tool で呼び出す:
- タイトルと本文は最終 body から抽出
- labels: policies.labels_hint
- `--repo policies.target_repo`（null の場合は省略）

### Step 6.5: project-board-sync

Step 6 の `/twl:issue-create` 出力 URL（`https://github.com/<owner>/<repo>/issues/<N>` 形式）から issue_number を抽出し、`/twl:project-board-sync <issue_number>` を Skill tool で呼び出す。

- issue_number: issue_url の末尾パスセグメント（`/issues/(\d+)` でマッチ）
- 失敗時は `OUT/report.json` の `warnings_acknowledged` リストに warning エントリを追加（非ブロッキング）。STATE は変更しない

### Step 7: 完了（MUST — 最終ステップ）

**report.json 書き込みは最終ステップとして必須。書き込み完了まで終了してはならない（MUST）。**

```bash
printf 'done\n' > "$PER_ISSUE_DIR/STATE"
```

`OUT/report.json` に以下を書き込む（**省略不可**）:
```json
{
  "status": "done",
  "issue_url": "<gh issue create の出力 URL>",
  "rounds": <実行したラウンド数>,
  "findings_final": <最終 aggregate.yaml の内容>,
  "warnings_acknowledged": <WARNING findings のリスト>
}
```

report.json 書き込み後、audit snapshot を実行する（audit 非アクティブ時は no-op）:
```bash
python3 -m twl.autopilot.audit snapshot \
  --source-dir "$PER_ISSUE_DIR" \
  --label "co-issue/$(basename "$PER_ISSUE_DIR")" 2>/dev/null || true
```

## STATE 遷移

| 値 | 意味 |
|---|---|
| `running` | 起動・初期化中 |
| `reviewing` | spec-review 実行中 |
| `fixing` | body 修正中 |
| `done` | 正常完了 |
| `failed` | 回復不能エラー |
| `circuit_broken` | max_rounds 到達・CRITICAL 未解消 |

## 自律実行制約（MUST）

- このワークフローは orchestrator から spawn された Worker セッションで実行される
- 全 Step を中断なく自律的に完了すること（MUST）
- AskUserQuestion は使用しないこと（MUST NOT）— プロンプト制約として機能
- エラー時は OUT/report.json に結果を書き込み exit すること

## ファイル経由 I/O 制約（MUST NOT）

- `IN/` 以外のパスを参照してはならない（ファイル入力として）
- env var 経由でデータを受け取ってはならない（パス指定は可）
- inject プロンプト経由のデータ（policies.json 主要フィールドなど）は、Worker の初期コンテキスト提供として受け取ることができる。ただし `IN/` ファイルを正規の入力源として引き続き使用すること（プロンプト経由データは補助的なコンテキストであり、`IN/` ファイルの代替ではない）

## 禁止事項（MUST NOT）

- N=1 ガード呼び出しを省略してはならない
- STATE ファイルへの書き込みを省略してはならない
- OUT/report.json の書き込みを省略してはならない（正常・異常どちらの終了でも必須）
