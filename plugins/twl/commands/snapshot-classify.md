---
type: atomic
tools: [AskUserQuestion, Bash, Read]
effort: low
maxTurns: 10
---
# スナップショット Tier 分類

プロジェクト内の全ファイルを AI が分析し、4 Tier に分類する。

## Tier 定義

| Tier | 役割 | テンプレートでの扱い |
|------|------|---------------------|
| 1 | インフラ設定 | プレースホルダ置換してコピー |
| 2 | 起動用スタブ | ビジネスロジック除去してスタブ化 |
| 3 | 参照情報 | AI 参考用としてマーク付き包含（各カテゴリ最大1ファイル） |
| 4 | 除外 | テンプレートに含めない |

## フロー制御（MUST）

### Step 1: 自動分類ルール適用

以下のパターンは自動的に Tier 4（除外）に分類:

- `.env`, `.env.*`（secrets）
- `*.key`, `*.pem`, `*.p12`（証明書）
- `credentials.*`, `*secret*`（認証情報）
- `*.lock`, `*.lockb`（ロックファイル）
- `supabase/migrations/*`（マイグレーション）
- `node_modules/`, `.venv/`, `__pycache__/`, `dist/`, `.next/`

secrets パターンに該当したファイルは警告を表示:

```
⚠ secrets 自動除外: .env, .env.local (Tier 4)
```

### Step 2: AI による分類

残りのファイルを以下の基準で AI が分類:

| 判定基準 | Tier |
|---------|------|
| プロジェクト設定（package.json, tsconfig, services.yaml, CLAUDE.md, hooks, config） | 1 |
| エントリポイント、barrel export、最小ルート定義（index.ts, app.ts, route定義） | 2 |
| 実装例として有用（ルート1つ、テスト1つ、スキーマ定義1つ） | 3 |
| ビジネスロジック、データファイル、テスト全般 | 4 |

### Step 3: ユーザー確認

分類結果をテーブル形式で表示し、AskUserQuestion で確認:

```
## Tier 分類結果

| # | ファイル | Tier | 理由 |
|---|---------|------|------|
| 1 | package.json | 1 | プロジェクト設定 |
| 2 | src/index.ts | 2 | エントリポイント |
| ... | ... | ... | ... |

修正が必要な行があれば番号と新しい Tier を指定してください（例: "3→1, 7→4"）。
問題なければ「OK」と入力してください。
```

ユーザーの修正を適用して最終分類を確定。

### Step 4: 分類結果を中間ファイルに保存

確定した分類結果を `--output` で指定されたパスに JSON 形式で保存（snapshot-generate で使用）:

```bash
# 出力パスは co-project-snapshot が mktemp で生成し引数で渡す
echo '<classify-result-json>' > <classify-result-path>
```

---

## 禁止事項（MUST NOT）

- ユーザー確認なしで分類を確定してはならない
- secrets ファイル（.env, *.key, *.pem, credentials.*）を Tier 1-3 に分類してはならない（MUST NOT）。ユーザーが Tier 変更を指示した場合は変更を拒否し、「secrets ファイルはテンプレートに含められません」と通知する
