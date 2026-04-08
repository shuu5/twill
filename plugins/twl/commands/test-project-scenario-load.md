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

## 処理フロー（MUST）

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

### Step 5: Issue ファイル配置

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

### Step 6: commit

```bash
cd "$TEST_TARGET"
git add -A
git commit -m "chore(test): load scenario <scenario-name>"
```

### Step 7: JSON 出力

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

## モード制約

- 本 atomic は `--local-only` モードのみ実装（GitHub Issue 起票なし）
- `--real-issues` モードは将来の別 Issue で実装予定
