# validate: 構造・型ルール検証

## 目的
生成されたプラグインの構造的正しさを検証する。

## 手順

### 1. ファイル存在確認
```bash
cd ~/ubuntu-note-system/claude/plugins/t-{name}
loom check
```

### 2. 型ルール検証
```bash
loom validate
```

### 2.5. deep-validate チェック
```bash
loom audit
```
- `[controller-bloat]`: controller/team-controller の行数（120行Warning, 200行Critical）
- `[ref-placement]`: reference の calls 宣言が実消費者にあるか
- `[tools-mismatch]`: frontmatter と body のツール宣言一致
- `[tools-unused]`: frontmatter 宣言あり body 未使用（Info）

### 2.7. workflow 検証

- `[workflow-frontmatter]`: workflow 型コンポーネントの `user-invocable` フィールド存在チェック。デフォルト `false` を推奨。フィールドが未定義の場合は Warning
- `[workflow-spawnable-by]`: workflow の `spawnable_by` が有効な値（`controller` または `user`）のいずれかであることを検証。無効な値の場合は Error

### 3. frontmatter 検証
各ファイルの frontmatter が型テンプレートに準拠しているか確認:
- skills/*/SKILL.md: name, description フィールド
- team-workflow: user-invocable: false
- workflow: user-invocable フィールド存在（デフォルト false 推奨）
- team-phase: allowed-tools
- team-worker (agents/): tools リスト

### 4. cross-reference 確認
- deps.yaml の calls が実在するコンポーネントを参照しているか
- workers リストのエントリが agents セクションに存在するか
- checkpoint_ref が reference スキルとして存在するか

### 5. プラグイン構造確認
```bash
claude plugin validate ~/ubuntu-note-system/claude/plugins/t-{name}
```

### 6. orphan ノード検出
```bash
loom orphans
```
- 全コンポーネントが上流から到達可能か確認
- orphan がある場合は Critical として報告
- 典型的な原因: controller の calls に追加忘れ、specialist の宣言漏れ

### 7. 依存ツリー表示
```bash
loom tree
```

### 8. README/SVG 整合性確認

#### 8a. README.md 存在チェック
```bash
ls -la README.md 2>/dev/null
```
- README.md が存在しない → **Warning**（generate Step 9 で生成必要）
- README.md に `DEPS-GRAPH-START` マーカーがない → **Warning**（依存グラフ未統合）
- README.md に「エントリーポイント」セクションがない → **Warning**（標準テンプレート非準拠）

#### 8b. SVG 整合性確認
deps.yaml と SVG が同期しているか確認:
```bash
# SVG が存在し、deps.yaml より新しいか確認
ls -la docs/deps.svg docs/deps-*.svg 2>/dev/null
```
- SVG が存在しない → **Warning**（`--update-readme` 必要）
- SVG が deps.yaml より古い → **Warning**（再生成推奨）

## 出力
検証結果のサマリー:
- OK / NG 件数
- 問題点のリスト（orphan 含む）
- 修正提案
