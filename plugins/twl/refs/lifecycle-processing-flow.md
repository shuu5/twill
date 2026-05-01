# workflow-issue-lifecycle 処理フロー詳細

`workflow-issue-lifecycle/SKILL.md` から切り出した処理フロー（全 Step）・スキーマ・制約の詳細。

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
if [[ "$PER_ISSUE_DIR" =~ \.\.(/|$) ]]; then
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

`round=0` で初期化し、ループ先頭で `round += 1` してから実行する（実効範囲: round=1 〜 max_rounds）:

```
round = round + 1   # round=1 から開始
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

### Step 6: issue 作成 + Status 書き込み（dual-write: label 先 → Status 後）

`/twl:issue-create` を Skill tool で呼び出す:
- タイトルと本文は最終 body から抽出
- labels: policies.labels_hint（Step 4.5 で追加された "refined" ラベルを含む）
- `--repo policies.target_repo`（null の場合は省略）

issue 作成後、labels_hint のラベルを付与する際は以下の dual-write パターンを適用する（AC1+AC2 と同等、#1209 準拠）:

```bash
# ISSUE_NUMBER: issue_url（/twl:issue-create 出力）の末尾パスセグメントから抽出
# TARGET_REPO: policies.target_repo（null の場合は既定リポジトリ）
# LABELS_HINT: jq -r '.labels_hint[]' "$PER_ISSUE_DIR/IN/policies.json" で取得

# idempotent auto-create pre-step（ADR-024 Phase 1; Phase B 移行で削除予定）
# label 不在時に --add-label が失敗して Status=Refined 移行が skip される連鎖を断つ
# 例: gh label create refined --color "8B5CF6" --description "auto-created" --repo "$TARGET_REPO" 2>/dev/null || true
while IFS= read -r label; do
  [[ -n "$label" ]] && gh label create "$label" --color "8B5CF6" --description "auto-created by workflow-issue-lifecycle" --repo "$TARGET_REPO" 2>/dev/null || true
done < <(jq -r '.labels_hint[]' "$PER_ISSUE_DIR/IN/policies.json")

# シェルレベル || true guard — loop が abort せず次 label に継続することを保証する
while IFS= read -r label; do
  [[ -n "$label" ]] && gh issue edit "$ISSUE_NUMBER" --repo "$TARGET_REPO" --add-label "$label" 2>/dev/null || true
done < <(jq -r '.labels_hint[]' "$PER_ISSUE_DIR/IN/policies.json")

# Status update 独立性保証 — label 付与 loop の結果（成功/失敗/部分失敗）と無関係に実行される。
# label 付与で発生した失敗は Status update を block しない（ADR-024 dual-write 独立性保証）。
bash "${SCRIPTS_ROOT:-plugins/twl/scripts}/chain-runner.sh" board-status-update "$ISSUE_NUMBER" Refined \
  2>/dev/null || echo "⚠️ Status=Refined への Board 更新失敗（label は付与済み）"
```

labels_hint に "refined" が含まれていれば Status=Todo を初期値として Board に登録する（project-board-sync で対応）。

責任境界: #943 gate は Status=Refined の有無のみ確認。phase-review の内容は #940 の責務。

**dual-write observability（Issue #1212）**: `/twl:issue-create` 完了後かつ Step 6.5 の前に、labels_hint に "refined" が含まれる場合は以下を実行する:

```bash
# refined-dual-write-log.sh を source（CLAUDE_PLUGIN_ROOT 不確定時の fallback あり）
source "${CLAUDE_PLUGIN_ROOT}/scripts/refined-dual-write-log.sh" 2>/dev/null || true

# label 付与 exit code に応じて dual_write_log を呼び出す
# 失敗時:
dual_write_log WARN label_add_failed "${ISSUE_NUMBER}" "label=refined repo=${TARGET_REPO} exit_code=${_exit}"
# 成功時:
dual_write_log OK dual_write "${ISSUE_NUMBER}" "label_ok=Y"
```

CLAUDE_PLUGIN_ROOT が不確定の場合の fallback: `bash -c 'source "${CLAUDE_PLUGIN_ROOT}/scripts/refined-dual-write-log.sh" && dual_write_log ...'` またはインライン `printf '[%s] WARN label_add_failed issue=#%s ...\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${ISSUE_NUMBER}" >> /tmp/refined-dual-write.log` を使用する。

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
