---
type: atomic
tools: [AskUserQuestion, Bash]
effort: medium
maxTurns: 10
---
# test-target リセット

test-target worktree を初期状態（`test-target/initial` tag）に戻す（`--mode local`）、または real-issues モードで作成されたリソースをクリーンアップする（`--real-issues`）。

## 引数

- `--mode local`: local worktree を初期状態に git reset（デフォルト動作）
- `--real-issues`: `.test-target/loaded-issues.json` に記録された PR/Issue/branch を一括削除
- `--older-than <duration>`: `loaded_at` が指定期間より古いエントリのみを対象（`d`=日, `w`=週, `m`=月）
- `--dry-run`: 削除予定リストのみ出力、実操作なし

## 処理フロー（MUST）

### Step 1: 引数解析と排他チェック

```bash
MODE_LOCAL=false
REAL_ISSUES=false
OLDER_THAN=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE_LOCAL=true; shift 2 ;;
    --real-issues) REAL_ISSUES=true; shift ;;
    --older-than) OLDER_THAN="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) shift ;;
  esac
done
```

`--mode local` と `--real-issues` が同時に指定された場合はエラー終了:

```bash
if $MODE_LOCAL && $REAL_ISSUES; then
  echo '{"error": "--mode local と --real-issues は同時に指定できません"}'
  exit 1
fi
```

`--older-than` が指定された場合、単位を検証して Epoch 変換:

```bash
if [[ -n "$OLDER_THAN" ]]; then
  VALUE="${OLDER_THAN%[dwm]}"
  UNIT="${OLDER_THAN: -1}"
  if ! [[ "$VALUE" =~ ^[0-9]+$ ]] || ! [[ "$UNIT" =~ ^[dwm]$ ]]; then
    echo "{\"error\": \"--older-than の形式が無効です: $OLDER_THAN （例: 30d, 2w, 1m）\"}"
    exit 1
  fi
  CUTOFF_EPOCH=$(date -d "-${VALUE} ${UNIT/d/days}" +%s 2>/dev/null || \
                 date -d "-${VALUE} ${UNIT/w/weeks}" +%s 2>/dev/null || \
                 date -d "-${VALUE} month" +%s 2>/dev/null)
fi
```

### Step 2: プロジェクトルート解決

```bash
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
BARE_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
TEST_TARGET="$BARE_ROOT/worktrees/test-target"
```

### Step 3: モード分岐

`$REAL_ISSUES == true` → Step 3-R（real-issues クリーンアップ）へ
それ以外 → Step 3-L（local モード）へ

---

#### Step 3-R: real-issues クリーンアップ

**Step 3-R-1: config.json から専用リポ取得**

```bash
CONFIG_JSON="$PROJECT_DIR/.test-target/config.json"
[[ -f "$CONFIG_JSON" ]] || { echo '{"error": ".test-target/config.json が見つかりません"}'; exit 1; }
REPO=$(jq -r '.repo' "$CONFIG_JSON")
```

**Step 3-R-2: loaded-issues.json 読み込み**

```bash
LOADED_JSON="$PROJECT_DIR/.test-target/loaded-issues.json"
[[ -f "$LOADED_JSON" ]] || { echo '{"error": ".test-target/loaded-issues.json が見つかりません"}'; exit 1; }
```

**Step 3-R-3: `--older-than` フィルタリング**

`$OLDER_THAN` が指定されている場合、`loaded_at` を Epoch 変換して `$CUTOFF_EPOCH` 以前のエントリのみを対象とする:

```bash
# jq で loaded_at をフィルタ（CUTOFF_EPOCH より古いもの）
ENTRIES=$(jq --argjson cutoff "${CUTOFF_EPOCH:-0}" '
  .issues[] | select(
    ($cutoff == 0) or
    ((.loaded_at // "") | if . == "" then false else (gsub("Z$";"") | strptime("%Y-%m-%dT%H:%M:%S") | mktime) < $cutoff end)
  )
' "$LOADED_JSON")
```

**Step 3-R-4: `--dry-run` 出力**

```bash
if $DRY_RUN; then
  echo "=== 削除予定リスト (dry-run) ==="
  echo "$ENTRIES" | jq -r '"PR#\(.pr_number // "なし") | Issue#\(.github_number) | branch: \(.branch)"'
  exit 0
fi
```

**Step 3-R-5: PR close → Issue close → branch 削除**

各エントリに対して順次実行:

```bash
echo "$ENTRIES" | jq -c '.' | while IFS= read -r entry; do
  pr_num=$(echo "$entry" | jq -r '.pr_number // empty')
  issue_num=$(echo "$entry" | jq -r '.github_number')
  branch=$(echo "$entry" | jq -r '.branch')

  # PR close（pr_number が存在する場合のみ）
  if [[ -n "$pr_num" ]]; then
    gh pr close "$pr_num" --repo "$REPO" 2>/dev/null \
      && echo "✓ PR#$pr_num close" \
      || echo "⚠️ PR#$pr_num close 失敗（既に closed の可能性）"
  fi

  # Issue close
  gh issue close "$issue_num" --repo "$REPO" 2>/dev/null \
    && echo "✓ Issue#$issue_num close" \
    || echo "⚠️ Issue#$issue_num close 失敗（既に closed の可能性）"

  # branch 削除
  git push "$REPO" --delete "$branch" 2>/dev/null \
    && echo "✓ branch $branch 削除" \
    || echo "⚠️ branch $branch 削除失敗（既に削除済みの可能性）"
done
```

**Step 3-R-6: JSON 出力**

```json
{
  "status": "cleaned",
  "repo": "<専用リポ>",
  "cleaned_count": <削除したエントリ数>
}
```

---

#### Step 3-L: local モード

**Step 3-L-1: test-target worktree 存在チェック**

```bash
[[ -d "$TEST_TARGET" ]] || { echo '{"error": "test-target worktree が存在しません。先に /twl:test-project-init を実行してください"}'; exit 1; }
```

**Step 3-L-2: cwd 安全確認（MUST）**

```bash
CURRENT_DIR="$(pwd)"
if [[ "$CURRENT_DIR" == "$TEST_TARGET"* ]]; then
  echo '{"error": "test-target worktree 内から reset は実行できません。worktree 外に移動してから再実行してください"}'
  exit 1
fi
```

### Step 4: ユーザー確認（MUST — `--mode local` 時のみ）

AskUserQuestion: 「test-target を初期状態に reset します。未 push の変更は失われます。続行しますか?」

- No → no-op で終了
- Yes → Step 5 へ

### Step 5: reset 実行（`--mode local` 時のみ）

```bash
cd "$TEST_TARGET"
git reset --hard test-target/initial
git clean -fdx
```

### Step 6: JSON 出力（`--mode local` 時）

```json
{
  "status": "reset",
  "path": "<worktree path>",
  "commit": "<test-target/initial の commit hash>",
  "file_count": <reset 後のファイル数>
}
```

## 禁止事項（MUST NOT）

- cwd が test-target 内の場合に local reset を実行してはならない
- `--mode local` 時はユーザー確認なしに reset を実行してはならない
- `--real-issues` 時に Step 4（ユーザー確認）および Step 5（git reset）を実行してはならない
- `--mode local` と `--real-issues` を同時に受け入れてはならない
- 正規表現マッチで削除対象 branch を決定してはならない（`loaded-issues.json` の明示リストを使うこと）
