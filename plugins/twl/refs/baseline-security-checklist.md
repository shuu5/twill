---
name: twl:baseline-security-checklist
description: |
  セキュリティチェックリスト。OWASP Top 10パターンテーブル、言語別脆弱性パターン、False Positiveリスト。
type: reference
disable-model-invocation: true
---

# Security Checklist Baseline

レビュアーが参照するセキュリティチェックリスト。OWASP Top 10パターンテーブルとFalse Positiveリストで精度と網羅性を向上させる。

## OWASP Top 10 パターンテーブル（2021）

| ID | カテゴリ | 検出パターン | 推奨対策 |
|----|---------|-------------|---------|
| A01 | Broken Access Control | ハードコードされたロールチェック、認可なしのエンドポイント、IDOR脆弱性、CSRFトークン未検証 | RBAC/ABACミドルウェア、リソース所有者チェック、RLSポリシー、SameSite Cookie + CSRFトークン |
| A02 | Cryptographic Failures | 平文パスワード保存、MD5/SHA1使用、HTTP通信、ハードコードされた暗号鍵 | bcrypt/argon2、TLS強制、環境変数で鍵管理 |
| A03 | Injection | 文字列結合SQL、未サニタイズのシェル実行、テンプレート直接挿入 | パラメータ化クエリ、ORM使用、コマンド引数配列渡し |
| A04 | Insecure Design | 認証なしの機密API、レート制限なし、多段階認証なし | 脅威モデリング、設計レビュー、Defense in Depth |
| A05 | Security Misconfiguration | デフォルト認証情報、詳細エラーメッセージ公開、不要な機能有効 | 最小権限原則、本番環境でデバッグ無効化 |
| A06 | Vulnerable Components | 既知脆弱性のある依存関係、更新されていないライブラリ | 依存関係スキャン、定期更新、lockfile管理 |
| A07 | Auth Failures | セッション固定化、弱いパスワードポリシー、JWT `alg: "none"` 受け入れ、HS256/RS256アルゴリズム混同攻撃、JWT署名未検証 | セッション再生成、MFA、アルゴリズム許可リスト固定、署名検証必須 |
| A08 | Data Integrity Failures | 未検証のデシリアライズ、CI/CDパイプラインの改ざん | 署名検証、信頼できるソースからのみ取得 |
| A09 | Logging Failures | 機密データのログ出力、監査ログなし、ログインジェクション | 構造化ログ、機密データマスキング、監査証跡 |
| A10 | SSRF | 未検証のURL入力でのHTTPリクエスト、内部ネットワークアクセス | URL許可リスト、内部ネットワークブロック |

## 言語別脆弱性パターン

### TypeScript / JavaScript

| パターン | リスク | 対策 |
|---------|-------|------|
| `eval()`, `new Function()` | コード実行 | 使用禁止。JSONパースは `JSON.parse()` |
| `innerHTML`, `dangerouslySetInnerHTML` | XSS | テキストは `textContent`、ReactはデフォルトでエスケープされるためJSXを使用 |
| `child_process.exec(userInput)` | コマンドインジェクション | `execFile()` + 引数配列 |
| `fs.readFile(userPath)` | パストラバーサル | `path.resolve()` + ベースディレクトリ検証 |
| `res.json({ error: err.stack })` | 情報漏洩 | 本番では汎用メッセージ、スタックトレースはログのみ |
| `obj[userInput] = value`, `_.merge(target, untrusted)` | Prototype Pollution | Object.create(null)、Map使用、入力キーの許可リスト検証 |
| `new RegExp(userInput)`, 複雑な正規表現にユーザー入力適用 | ReDoS | 正規表現を定数化、ユーザー入力にはリテラルマッチ使用 |
| CSRF トークンなしの状態変更 API | CSRF | SameSite=Strict/Lax Cookie、CSRF トークン検証、Origin ヘッダー確認 |

### Python

| パターン | リスク | 対策 |
|---------|-------|------|
| `os.system()`, `subprocess.shell=True` | コマンドインジェクション | `subprocess.run(args_list, shell=False)` |
| `pickle.loads(user_data)` | 任意コード実行 | `json` 使用、信頼できないデータに pickle 禁止 |
| `f"SELECT * FROM users WHERE id={uid}"` | SQLインジェクション | パラメータ化クエリ、ORM |
| `yaml.load(data)` | コード実行 | `yaml.safe_load()` |
| `open(user_path)` | パストラバーサル | `pathlib.Path.resolve()` + 親ディレクトリ検証 |

### bash 入力検証

bash スクリプトで受け取るパス・識別子・列挙値の検証は **allowlist regex 方式** を採用する。詳細な規約・パターン例・prior art は [`baseline-bash.md` §11](baseline-bash.md) を参照。

| パターン | リスク | 対策 |
|---------|-------|------|
| blocklist 方式（禁止文字列の列挙）によるパス検証 | パストラバーサル（参照: 上記 TypeScript/Python 節） | allowlist regex `^[A-Za-z0-9._/-]+$` で受理パターンを明示 |
| 未検証の識別子（issue 番号・ブランチ名・skill 名）を shell コマンドに渡す | コマンドインジェクション | 数値: `^[1-9][0-9]*$`、識別子: `^[A-Za-z0-9._-]+$` で allowlist 検証 |
| 列挙値の未検証（severity・action 等） | 想定外の値による処理分岐 | `case "$VAR" in val1\|val2) ;; *) exit 1 ;; esac` で allowlist 列挙 |

**パストラバーサルとの関係**: TypeScript の `path.resolve()` / Python の `pathlib.Path.resolve()` に相当する bash の対策が allowlist regex によるパス検証である。`*..* ` や `^/` の blocklist チェックは網羅性が保証されないため採用しない（→ [`baseline-bash.md` §11](baseline-bash.md) 参照）。

## False Positive リスト

以下のパターンは**報告しない**（誤検出リスクが高い）:

### ORM / クエリビルダー

- **Prisma / Drizzle / SQLAlchemy のクエリ**: パラメータ化が自動適用されるため、SQLインジェクションとして報告しない
- **Supabase client のRPC呼び出し**: PostgREST経由でパラメータ化される
- **TypeORM / Sequelize のfindメソッド**: ORM内部でエスケープ済み

### フレームワーク組み込みエスケープ

- **React JSX内の変数展開**: `{variable}` はデフォルトでエスケープされる（`dangerouslySetInnerHTML` 以外）
- **Next.js Server Components**: レンダリング時に自動エスケープ
- **Jinja2 autoescapeモード**: テンプレート変数は自動エスケープ

### シークレット管理

- **環境変数経由の認証情報**: `process.env.API_KEY` / `os.environ["API_KEY"]` は適切な管理方法
- **Docker secrets / Kubernetes secrets**: マウントされたファイルからの読み取りは安全
- **.env ファイルが .gitignore に含まれている**: `.gitignore` に `.env` が記載されていることを Read ツールで確認した上で免除する。未確認の場合は報告すること

### その他

- **テストコード内のハードコード値**: テスト用のモック値・フィクスチャは問題なし
- **定数ファイル内のURL/パス**: 設定値としてのハードコードは秘密情報でなければ安全
- **型定義内のリテラル型**: TypeScriptのリテラル型はコードではない
