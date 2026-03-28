# Warning ベストエフォート修正

レビューで検出された WARNING finding をベストエフォートで修正する。
修正失敗時は revert し、未修正分は tech-debt Issue として起票する。

## 入力

- WARNING findings リスト（phase-review の結果から severity=WARNING を抽出）

## 出力

- 修正結果（修正済み / revert 済み / tech-debt Issue 起票済み）

## 実行ロジック（MUST）

### Step 1: WARNING findings の選別

```
スコープ内の WARNING findings のみを対象とする
severity=INFO は対象外
```

### Step 2: 修正試行

各 WARNING finding に対して:

1. 修正を実施
2. 変更ファイルの構文チェック
3. 成功 → コミット、失敗 → `git checkout -- <file>` で revert

### Step 3: 未修正分の処理

修正できなかった WARNING は tech-debt Issue として起票:

```
gh issue create --title "tech-debt: ${finding.message}" \
  --label "tech-debt"
```

### 制約

- WARNING 修正に費やす時間は 1 finding あたり最大 2 分
- 修正が他のテストを破壊する場合は即座に revert
