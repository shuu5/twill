# 開発サービス起動管理

プロジェクトに必要なサービス群を起動・停止・確認するコマンド。

## 使用方法

```
/twl:services [action]
```

## アクション

| アクション | 説明 |
|-----------|------|
| `up` | 必要なサービスを起動（デフォルト） |
| `down` | サービスを停止 |
| `status` | サービス状態を確認 |
| `logs` | サービスログを表示 |

## 起動判定ロジック

**プライマリソース**: `services.yaml`（プロジェクトルート）

1. **services.yaml が存在する場合**: YAML に従って起動
2. **services.yaml がない場合**: プロジェクトタイプを自動検出し、テンプレートから生成を提案

## services.yaml 形式

```yaml
services:
  - name: webapp-dev
    type: container
    script: ~/container-manager/webapp-dev/run.sh
    required: true
    healthcheck:
      command: curl -s http://localhost:3000 > /dev/null
      timeout: 30

  - name: supabase
    type: supabase-local
    project_path: .
    required: false

  - name: dev-server
    type: command
    command: pnpm dev
    cwd: frontend/
    background: true
```

### サービスタイプ

| type | 説明 | 必須フィールド |
|------|------|---------------|
| `container` | Podman コンテナ | `script` |
| `supabase-local` | Supabase Local | `project_path` |
| `command` | 任意のシェルコマンド | `command` |

## 実行フロー

### /twl:services up

1. services.yaml を読み込み
2. 各サービスを順番に起動
   - container: script を実行
   - supabase-local: supabase-local.sh start
   - command: background 実行
3. healthcheck があれば疎通確認
4. 起動結果を報告

### /twl:services status

1. services.yaml を読み込み
2. 各サービスの状態を確認
   - container: `podman ps` でコンテナ状態
   - supabase-local: `supabase status`
   - command: プロセス存在確認
3. 状態一覧を表示

### /twl:services down

1. services.yaml を読み込み
2. 逆順でサービスを停止

## services.yaml 未検出時の自動生成

### Step 1: プロジェクト情報検出

```bash
# プロジェクト名（worktree 対応）
if [ -f ".git" ]; then
  PROJECT_NAME=$(basename "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")")
else
  PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
fi

# プロジェクト名サニタイズ（シェルメタ文字を排除）
if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: プロジェクト名に不正な文字が含まれています: $PROJECT_NAME" >&2
    exit 1
fi

# プロジェクトタイプ判定
if [ -d "apps/backend" ] && [ -d "packages/schema" ]; then
    TYPE="webapp-hono"
elif [ -d "backend" ] && [ -d "frontend" ]; then
    TYPE="webapp-llm"
else
    TYPE="unknown"
fi
```

### Step 2: テンプレート読み込み・置換

- TYPE が `webapp-hono` or `webapp-llm` → `~/.claude/templates/${TYPE}/services.yaml.template` を Read し `{{PROJECT_NAME}}` を置換
- TYPE が `unknown` → 手動作成を案内

### Step 3: ユーザー確認・書き込み

1. 生成内容をプレビュー表示
2. ユーザーに確認
3. `services.yaml` をプロジェクトルートに書き込み

## 禁止事項（MUST NOT）

- ユーザー確認なしに services.yaml を自動生成してはならない
