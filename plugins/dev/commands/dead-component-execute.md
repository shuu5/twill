# Dead Component 削除実行

ユーザーが選択した Dead Component を削除し、整合性を検証する。

## 入力

workflow-dead-cleanup から以下のコンテキストが渡される:
- plugin_dir: 対象プラグインディレクトリ
- 選択されたコンポーネントリスト（ID・ファイルパス・外部参照情報）

## フロー（MUST）

### Step 1: パス検証とファイル削除

選択された各コンポーネントについて:

**外部参照二重チェック**: コンポーネントに外部参照フラグがある場合、controller で確認済みでも警告を表示し、フラグを再確認する。外部参照ありかつ controller 確認なしの場合はスキップする。

**パス検証（MUST）**: 削除前に `file_path` が `plugin_dir` 配下であることを確認する。検証後は正規化済みパスを使用して削除する:

```bash
# realpath で正規化し、plugin_dir 配下であることを検証
REAL_PATH=$(realpath "<file_path>")
REAL_PLUGIN=$(realpath "<plugin_dir>")
if [[ "$REAL_PATH" != "$REAL_PLUGIN"/* ]]; then
  echo "⚠️ パス検証失敗: $REAL_PATH は $REAL_PLUGIN 配下ではありません。スキップします。"
  # この項目をスキップして次へ
fi
```

検証通過後に**正規化済みパス**を使用してファイルを削除:

```bash
# ファイルが存在する場合のみ削除（正規化済み $REAL_PATH を使用）
rm "$REAL_PATH"
# ディレクトリ型の場合（skills/xxx/ ディレクトリ）も同様に正規化して検証
REAL_DIR=$(realpath "<dir_path>")
if [[ "$REAL_DIR" != "$REAL_PLUGIN"/* ]]; then
  echo "⚠️ パス検証失敗: $REAL_DIR は $REAL_PLUGIN 配下ではありません。スキップします。"
fi
rm -r "$REAL_DIR"
```

ファイルが存在しない場合: deps.yaml エントリのみ削除し、警告を表示。

### Step 2: deps.yaml エントリ削除

deps.yaml の該当セクション（skills/commands/agents）から対象エントリを削除。
YAML 構造を壊さないよう注意。

### Step 3: 整合性検証

#### 3a. loom check 実行

```bash
cd <plugin_dir>
loom check 2>&1
```

**成功時**:
→ Step 3b へ

**失敗時**:
→ エラー内容を表示し、以下を案内:
```
⚠️ 整合性チェックに失敗しました。以下でリバートできます:
  git checkout HEAD -- deps.yaml <削除したファイルパスを列挙>
```
→ ワークフロー終了（SVG 再生成はスキップ）

#### 3b. SVG 再生成

```bash
cd <plugin_dir>
loom update-readme 2>&1
```

### Step 4: 結果サマリー

```
## 削除完了サマリー

- 削除コンポーネント数: N 件
- 削除ファイル:
  - skills/xxx.md
  - commands/yyy.md
- loom check: ✓ 成功
- SVG 再生成: ✓ 成功

次のステップ:
  git add -A && git commit
```

---

## エラーハンドリング

| エラー | 対応 |
|--------|------|
| パス検証失敗 | 警告表示、該当項目スキップ、続行 |
| ファイル削除失敗 | 警告表示、続行 |
| deps.yaml パース失敗 | エラー内容を表示、ワークフロー終了 |
| loom check 失敗 | リバート案内、ワークフロー終了 |

---

## 禁止事項（MUST NOT）

- **パス検証なしでファイルを削除してはならない**
- **loom check 失敗時に SVG 再生成を実行してはならない**
- **外部参照ありコンポーネントを警告なしで削除してはならない**（controller で確認済みだが二重チェック）
