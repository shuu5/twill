# スナップショットテンプレート生成

Tier 分類結果に基づいてテンプレートファイル群と manifest.yaml を生成する。

## フロー制御（MUST）

### Step 1: 出力ディレクトリ作成

```bash
mkdir -p "$HOME/.claude/templates/<template-name>"
```

### Step 2: Tier 1 ファイル処理

Tier 1 に分類されたファイルをコピーし、プロジェクト固有値をプレースホルダに置換:

- プロジェクト名 → `{{PROJECT_NAME}}`
- ファイル名に `.template` 拡張子を付与（元の拡張子の後に追加）

例: `package.json` → `package.json.template`（内容の固有値をプレースホルダ化）

### Step 3: Tier 2 ファイル処理

Tier 2 に分類されたファイルからビジネスロジックを除去し、最小スタブを生成:

- import 文、型定義は保持
- 関数・ハンドラの中身を空にする（コメントで `// TODO: implement` を追加）
- ディレクトリ構造は保持

### Step 4: Tier 3 ファイル処理

Tier 3 に分類されたファイルをそのままコピーし、先頭にマークを追加:

```
// [AI Reference] このファイルは実装例です。新プロジェクトでは参考として使用してください。
```

各カテゴリ（ルート、テスト、スキーマ）最大1ファイルに制限。

### Step 5: manifest.yaml 生成

snapshot-analyze の検出結果と Tier 分類結果を基に manifest.yaml を生成:

```yaml
name: <template-name>
description: |
  <ソースプロジェクトから抽出されたテンプレート>

stack:
  # snapshot-analyze の検出結果

containers:
  # snapshot-analyze の検出結果

placeholders:
  PROJECT_NAME:
    description: "プロジェクト名"
    default: null

tiers:
  # 確定した Tier 分類を glob パターンに変換

post_create: |
  # AI が適切なセットアップ手順を生成
```

### Step 6: 生成結果サマリー

```
テンプレート生成完了: ~/.claude/templates/<template-name>/
  Tier 1 (インフラ): N ファイル
  Tier 2 (スタブ): N ファイル
  Tier 3 (参照): N ファイル
  Tier 4 (除外): N ファイル
  manifest.yaml: 生成済み
```

---

## 禁止事項（MUST NOT）

- Tier 4 に分類されたファイルをテンプレートに含めてはならない
- ソースプロジェクトのファイルを変更してはならない
