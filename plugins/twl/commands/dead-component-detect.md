# Dead Component 検出

twl complexity で Dead Component を検出し、情報を収集・表示する。

## 入力

workflow-dead-cleanup から以下のコンテキストが渡される:
- plugin_dir: 対象プラグインディレクトリ
- `--plugin` オプション値（省略時はカレントディレクトリ）

## フロー（MUST）

### Step 1: Dead Component 検出

プラグインディレクトリで `twl complexity` を実行し、Dead Components セクションをパースする。

```bash
cd <plugin_dir>
twl complexity 2>&1
```

出力の `## Dead Components` セクションからテーブルをパース:
- `| Component | Type |` ヘッダーの後の各行から component ID と type を抽出
- component ID 形式: `skill:xxx`, `command:xxx`, `agent:xxx`

**0件の場合**（"No dead components found." を含む）:
→ 「Dead Component は検出されませんでした」と表示して正常終了。

### Step 2: 情報収集と表示

検出された各 Dead Component について以下の情報を収集:

#### 2a. ファイルパス取得

deps.yaml から該当エントリの `path` フィールドを読み取る:

```
component ID が "skill:xxx" → deps.yaml の skills.xxx.path
component ID が "command:xxx" → deps.yaml の commands.xxx.path
component ID が "agent:xxx" → deps.yaml の agents.xxx.path
```

#### 2b. 最終変更日取得

```bash
git log -1 --format='%ci' -- <file_path>
```

#### 2c. cross-plugin 参照チェック

他プラグインの deps.yaml と .md ファイルからコンポーネント名を grep:

```bash
# コンポーネント名のバリデーション（英数字・コロン・ハイフン・アンダースコアのみ許可）
if [[ ! "$component_name" =~ ^[a-zA-Z0-9:_-]+$ ]]; then
  echo "⚠️ 不正なコンポーネント名: $component_name（スキップ）"
  continue
fi

# 対象プラグイン以外の全プラグインディレクトリ
PLUGIN_ROOT=$(dirname <plugin_dir>)
for other_plugin in "$PLUGIN_ROOT"/*/; do
  [ "$other_plugin" = "<plugin_dir>/" ] && continue
  [ "$(basename "$other_plugin")" = "_shared" ] && continue
  grep -rl -- "$component_name" "$other_plugin" 2>/dev/null
done
```

- 検出あり → 「外部参照あり」フラグ + 参照元ファイルパスを記録
- 検出なし → 安全に削除可能

#### 2d. 一覧テーブル表示

```
## Dead Component 一覧

| # | コンポーネント | 型 | ファイル | 最終変更日 | 外部参照 |
|---|---------------|-----|---------|-----------|---------|
| 1 | skill:xxx     | atomic | skills/xxx.md | 2025-01-01 | なし |
| 2 | command:yyy   | atomic | commands/yyy.md | 2024-12-15 | ⚠️ env/deps.yaml |

※ 到達不能理由: いずれの entry_point からも calls チェーンで到達できないコンポーネント
```

---

## 禁止事項（MUST NOT）

- **検出結果を改変してはならない**: twl complexity の出力をそのまま反映
- **reference 型コンポーネントを検出対象に含めてはならない**（twl が除外済みだが二重チェック）
