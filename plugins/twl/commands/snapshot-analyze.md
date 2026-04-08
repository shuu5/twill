---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 10
---
# スナップショット分析

ソースプロジェクトを分析し、スタック情報とコンテナ依存を自動検出する。

## フロー制御（MUST）

### Step 1: ファイル構造スキャン

ソースプロジェクトのファイル一覧を取得（.git, node_modules, .venv, __pycache__ は除外）:

```bash
find <source-path> -type f \
  -not -path '*/.git/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.venv/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/dist/*' \
  -not -path '*/.next/*' \
  | head -500
```

### Step 2: スタック自動検出

以下のファイルの存在をチェックし、スタック情報を推定:

| ファイル | 検出結果 |
|---------|----------|
| `package.json` + `bun.lockb` | runtime: bun |
| `package.json` + `package-lock.json`/`pnpm-lock.yaml` | runtime: node |
| `renv.lock` | runtime: r |
| `pyproject.toml`/`uv.lock` | runtime: python |
| `next.config.*` | frontend: nextjs |
| `apps/backend/` + hono import | backend: hono |
| `requirements.txt` + fastapi import | backend: fastapi |
| `supabase/` | database: supabase |
| `litellm_config.yaml`/LiteLLM参照 | llm: litellm |
| `playwright.config.*` | testing: playwright |
| `packages/schema/` + Zod import | schema: zod |
| `docs/schema/openapi.yaml` | schema: openapi |

### Step 3: コンテナ依存検出

`services.yaml` または `docker-compose.yml` からコンテナ情報を抽出:

```bash
cat <source-path>/services.yaml 2>/dev/null
cat <source-path>/docker-compose.yml 2>/dev/null
```

### Step 4: 結果出力

検出結果をテーブル形式で出力:

```
## プロジェクト分析結果: <source-path>

### スタック
| 項目 | 検出値 | 根拠 |
|------|--------|------|
| runtime | bun | bun.lockb 存在 |
| ... | ... | ... |

### コンテナ依存
| コンテナ | 種別 | ソース |
|---------|------|--------|
| webapp-dev | required | services.yaml |
| ... | ... | ... |

### ファイル統計
- 総ファイル数: N
- ディレクトリ数: N
```

---

## 禁止事項（MUST NOT）

- ソースプロジェクトのファイルを変更してはならない
