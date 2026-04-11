---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 15
---
# テストシナリオ読み込み

test-target worktree にテストシナリオのダミー Issue をローカルファイルとして配置する。

## 引数

- `--scenario <name>` (必須): シナリオ名（例: `smoke-001`）
- `--real-issues` (省略可): GitHub 上の専用テストリポに実 Issue として起票する
- `--local-only` (省略可): ローカルファイル生成モードを明示指定する（デフォルト動作と同一）
- `--force` (省略可): `--real-issues` 使用時に既存の `loaded-issues.json` を無視して強制再起票する

## 処理フロー（MUST）

### Step 0: モード判定

`--real-issues` フラグの有無を確認し、フロー分岐を決定する。

```bash
REAL_ISSUES=false
FORCE=false
SCENARIO=""

for arg in "$@"; do
  case "$arg" in
    --real-issues) REAL_ISSUES=true ;;
    --local-only)  REAL_ISSUES=false ;;  # デフォルト動作と同一（明示用エイリアス）
    --force)       FORCE=true ;;
    --scenario)    ;;
    *)             [[ "${prev:-}" == "--scenario" ]] && SCENARIO="$arg" ;;
  esac
  prev="$arg"
done
```

- `REAL_ISSUES=true` → **real-issues フロー**（Step 1〜3 の後、Step 3a〜3f を実行）
- `REAL_ISSUES=false` → **local フロー**（既存の Step 5〜7 を実行）

### Step 1: プロジェクトルート解決

```bash
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
BARE_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
TEST_TARGET="$BARE_ROOT/worktrees/test-target"
```

### Step 2: 存在チェック

```bash
[[ -d "$TEST_TARGET" ]] || { echo '{"error": "test-target worktree が存在しません。先に /twl:test-project-init を実行してください"}'; exit 1; }
```

### Step 3: シナリオカタログ参照

`refs/test-scenario-catalog.md` を Read する。存在しない場合は以下の組み込み stub catalog を使用:

```yaml
smoke-001:
  level: smoke
  issues: 1
  description: "単一 Issue, trivial change"
  issue_templates:
    - id: "TEST-001"
      title: "[Test] add hello world function"
      body: |
        ## 概要
        scripts/helper.sh に hello_world 関数を追加する。
        ## 受け入れ基準
        - [ ] hello_world 関数が存在する
        - [ ] 呼び出すと "Hello, World!" を stdout に出力する
      labels: [test, scope/test-target]

smoke-002:
  level: smoke
  issues: 2
  description: "2 Issue, 依存なし"
  issue_templates:
    - id: "TEST-001"
      title: "[Test] add greeting function"
      body: |
        ## 概要
        scripts/helper.sh に greet 関数を追加する。
        ## 受け入れ基準
        - [ ] greet <name> で "Hello, <name>!" を出力する
      labels: [test, scope/test-target]
    - id: "TEST-002"
      title: "[Test] add version command"
      body: |
        ## 概要
        scripts/helper.sh に version 関数を追加する（出力: "0.1.0"）。
        ## 受け入れ基準
        - [ ] version 関数が "0.1.0" を出力する
      labels: [test, scope/test-target]
```

### Step 4: シナリオ検証

指定された `--scenario` がカタログに存在しない場合:
```
echo '{"error": "シナリオ '<name>' が見つかりません"}' >&2
exit 1
```

### Step 5（local フロー）: Issue ファイル配置

各 `issue_template` について:

```bash
ISSUES_DIR="$TEST_TARGET/.test-target/issues"
mkdir -p "$ISSUES_DIR"

# 既存 Issue ファイルをクリア
rm -f "$ISSUES_DIR"/*.md

# 各 Issue を配置
cat > "$ISSUES_DIR/<id>.md" << 'EOF'
---
id: <id>
title: <title>
labels: [<labels>]
status: open
---

<body>
EOF
```

### Step 6（local フロー）: commit

```bash
cd "$TEST_TARGET"
git add -A
git commit -m "chore(test): load scenario <scenario-name>"
```

### Step 7（local フロー）: JSON 出力

```json
{
  "status": "loaded",
  "scenario": "<scenario-name>",
  "level": "<level>",
  "issues": ["<id1>", "<id2>"],
  "issue_count": <count>,
  "commit": "<commit hash>"
}
```

---

## real-issues フロー（`--real-issues` 指定時）

Step 0〜4 の共通処理後、以下のステップを実行する。

### Step 3a: config.json 読み込みとモード検証

`.test-target/config.json` を読み込んで `mode` と `repo` を取得する。

```bash
CONFIG_PATH="$TEST_TARGET/.test-target/config.json"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo '{"error": "config.json が見つかりません。先に /twl:test-project-init を実行してください"}' >&2
  exit 1
fi

MODE=$(jq -r '.mode' "$CONFIG_PATH")
REPO=$(jq -r '.repo // empty' "$CONFIG_PATH")

if [[ "$MODE" != "real-issues" ]]; then
  echo '{"error": "--real-issues を使うには test-project-init --mode real-issues で初期化してください"}' >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  echo '{"error": "config.json に repo フィールドがありません"}' >&2
  exit 1
fi
```

### Step 3b: 二重起票ガード

```bash
LOADED_ISSUES_PATH="$TEST_TARGET/.test-target/loaded-issues.json"

if [[ -f "$LOADED_ISSUES_PATH" ]]; then
  existing_scenario=$(jq -r '.scenario // empty' "$LOADED_ISSUES_PATH" 2>/dev/null || echo "")
  if [[ "$existing_scenario" == "$SCENARIO" ]]; then
    if [[ "$FORCE" != "true" ]]; then
      echo "{\"status\":\"skipped\",\"reason\":\"already loaded\",\"scenario\":\"$SCENARIO\"}"
      exit 0
    fi
    # --force: 既存 Issue をクローズ
    existing_repo=$(jq -r '.repo // empty' "$LOADED_ISSUES_PATH")
    while IFS= read -r num; do
      [[ -z "$num" ]] && continue
      gh issue close "$num" --repo "$existing_repo" 2>/dev/null || true
    done < <(jq -r '.issues[].number' "$LOADED_ISSUES_PATH" 2>/dev/null || true)
  fi
fi
```

### Step 3c: gh issue create で実 Issue を起票

各 `issue_template` を `gh issue create` で起票し、Issue 番号と URL を収集する。

```bash
CREATED_ISSUES="[]"

for each issue_template in scenario:
  URL=$(gh issue create \
    --repo "$REPO" \
    --title "<title>" \
    --body "<body>" \
    --label "<labels comma-separated>")
  NUMBER="${URL##*/}"
  CREATED_ISSUES=... append {"id":"<id>","number":<N>,"url":"<url>"}
```

### Step 3d: loaded-issues.json 生成

```bash
LOADED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -n \
  --arg scenario "$SCENARIO" \
  --arg repo "$REPO" \
  --arg loaded_at "$LOADED_AT" \
  --argjson issues "$CREATED_ISSUES" \
  '{"scenario":$scenario,"repo":$repo,"loaded_at":$loaded_at,"issues":$issues}' \
  > "$TEST_TARGET/.test-target/loaded-issues.json"
```

### Step 3e: commit

```bash
cd "$TEST_TARGET"
git add .test-target/loaded-issues.json
git commit -m "chore(test): load real-issues <scenario-name>"
```

### Step 3f: JSON 出力

```json
{
  "status": "loaded",
  "mode": "real-issues",
  "scenario": "<scenario-name>",
  "repo": "<owner/repo>",
  "level": "<level>",
  "issues": ["<id1>", "<id2>"],
  "issue_count": <count>,
  "commit": "<commit hash>"
}
```
