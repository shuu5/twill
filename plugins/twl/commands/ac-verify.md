---
type: atomic
tools: [Agent, Bash, Read]
effort: medium
maxTurns: 30
---
# AC 検証（AC↔diff/test 整合性チェック）

## Context (auto-injected)
- Issue: !`source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo ""`
- Branch: !`git branch --show-current 2>/dev/null || echo ""`

PR diff・テスト結果・レビュー結果を Issue の受け入れ基準（AC）と機械的に照合し、
未達成 AC を CRITICAL Finding として報告する。merge-gate と連動し、未達成があれば REJECT を導く。

本コマンドは LLM 判断ステップ（chain-runner.sh の `step_ac_verify` がマーカーとして位置を記録する）。

## 入力

- AC チェックリスト: `${SNAPSHOT_DIR}/01.5-ac-checklist.md`（ac-extract の出力。`SNAPSHOT_DIR` 未設定時は `.dev-session/`）
- PR diff: `git diff --stat origin/main` + `git diff origin/main`
- 変更ファイル一覧: `git diff --name-only origin/main`
- pr-test の checkpoint: `python3 -m twl.autopilot.checkpoint read --step pr-test --field status`（存在すれば）

## 出力

- ac-verify checkpoint（`.autopilot/checkpoints/ac-verify.json`）
- 各 AC 項目の判定（達成 / 未達成 / 手動確認要 / 達成 (diff-only)）
- merge-gate が読み込める Findings 配列

## 実行ロジック（MUST）

### Step 0: 入力収集

```bash
SNAPSHOT_DIR="${SNAPSHOT_DIR:-.dev-session}"
AC_FILE="${SNAPSHOT_DIR}/01.5-ac-checklist.md"

if [[ ! -f "$AC_FILE" ]]; then
  # AC が抽出されていなければ WARN で抜ける
  python3 -m twl.autopilot.checkpoint write --step ac-verify --status WARN --findings '[]'
  echo "ac-verify: AC checklist 不在 — スキップ (WARN)"
  exit 0
fi

DIFF_STAT="$(git diff --stat origin/main 2>/dev/null || true)"
DIFF_FILES="$(git diff --name-only origin/main 2>/dev/null || true)"
DIFF_BODY="$(git diff origin/main 2>/dev/null || true)"
PR_TEST_STATUS="$(python3 -m twl.autopilot.checkpoint read --step pr-test --field status 2>/dev/null || echo "")"
```

### Step 1: AC 項目ごとの判定（LLM 判断）

各 AC 項目について以下のロジックで判定する。

| 入力条件 | 判定 | severity |
|---|---|---|
| 対応するテストが PASS（pr-test status = PASS） | 達成 | — |
| 対応するテストが FAIL（pr-test status = FAIL） | 未達成 | CRITICAL |
| 対応するテストなし + diff にキーワード一致あり | 達成 (diff-only) | WARNING |
| 対応するテストなし + diff にキーワード一致なし | 未達成 | CRITICAL |
| AC が手動確認要（UI 確認・本番デプロイ確認等） | 手動確認要 | WARNING |

**diff キーワード照合**: AC 文面から名詞句（ファイル名・関数名・コンポーネント名・コマンド名）を抽出し、`DIFF_FILES` および `DIFF_BODY` に出現するか確認する。AI による意味的解釈を許可するが、判定根拠を Finding の `evidence` に必ず記載すること。

### Step 1.5: PR 外副作用 verify（新規）

AC から以下の副作用キーワードを含む項目を抽出し、該当 API で現状態を verify する。

**副作用キーワード（正規表現、部分一致）**:
- `Issue にコメント` / `gh issue comment` / `comment.*Issue`
- `gh label` / `ラベル追加` / `--add-label`
- `README` / `ドキュメント更新` / `docs?/`
- `architecture/`

```bash
ISSUE_NUM="$(source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null; resolve_issue_num)"
if [[ -n "$ISSUE_NUM" ]]; then
  ALL_COMMENTS="$(gh issue view "$ISSUE_NUM" --json comments -q '.comments[].body' 2>/dev/null || true)"
fi
```

副作用キーワードを含む AC 項目それぞれについて:
1. `ALL_COMMENTS` を取得（全コメントをまとめて参照）
2. LLM が「該当内容が任意のコメントに含まれているか」を判定
3. 未達成の場合は以下の Finding を生成し、後続の Step 2 で Findings 配列に append する:

```json
{
  "severity": "WARNING",
  "category": "ac-side-effect-missing",
  "confidence": 75,
  "message": "AC『...』は Issue comment 等の PR 外副作用を要求しているが、Issue #N のコメントに該当内容が見当たらない",
  "evidence": "副作用キーワード: <keyword> / Issue comments: <取得件数>件"
}
```

ISSUE_NUM が解決できない場合、または副作用キーワードを含む AC 項目がない場合はスキップする。

### Step 2: Findings 構築

未達成または diff-only の AC それぞれについて Finding を生成する。
ref-specialist-output-schema 準拠:

```json
{
  "severity": "CRITICAL",
  "category": "bug",
  "confidence": 80,
  "message": "AC #N『...』の実装が diff/test に確認できない",
  "evidence": "diff には XXX への変更が見当たらない / pr-test FAIL"
}
```

**注**: `category: ac-alignment` enum は Issue #135 (worker-issue-pr-alignment specialist) で
ref-specialist-output-schema に追加される予定。Issue #135 完了前は暫定で `category: bug` を使用する。

### Step 3: ステータス算出

```
CRITICAL Finding が 1 件以上 → status=FAIL
WARNING Finding のみ → status=WARN
Finding なし → status=PASS
```

### Step 4: checkpoint 書き出し（MUST）

```bash
FINDINGS_JSON='[ ... 構築した Findings 配列 ... ]'
STATUS="FAIL"  # or WARN, PASS

python3 -m twl.autopilot.checkpoint write \
  --step ac-verify \
  --status "$STATUS" \
  --findings "$FINDINGS_JSON"
```

### Step 5: Issue コメント投稿（任意）

```bash
ISSUE_NUM="$(source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null; resolve_issue_num)"
if [[ -n "$ISSUE_NUM" ]]; then
  gh issue comment "$ISSUE_NUM" --body "$(cat <<EOF
## AC 検証結果 (ac-verify)

- 判定: $STATUS
- AC 項目数: $AC_COUNT
- 未達成: $UNMET_COUNT
- 達成 (diff-only): $DIFF_ONLY_COUNT
- 達成: $MET_COUNT

(詳細: $FINDINGS_SUMMARY)
EOF
)"
fi
```

## merge-gate 連動

merge-gate は本ステップの checkpoint を読み込み、CRITICAL Finding を BLOCKING 集合に統合する。
詳細は `commands/merge-gate.md` の「severity フィルタ判定」セクションを参照。

## 設計方針

- 機械的にできる照合（diff キーワード・テスト結果）は機械化
- 意味的判断（AC 文面の解釈）のみ LLM に委ねる
- 全判定は ref-specialist-output-schema 準拠の Finding として永続化される
- merge-gate との接続は checkpoint ファイル経由（疎結合）
