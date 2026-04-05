# verify: 統合検証+5原則チェック

## 目的
fix で適用した修正が正しく機能するかを総合的に検証する。

## validate との違い
- **validate**: 構造的正しさ（ファイル存在、型ルール、frontmatter形式）
- **verify**: 品質・動作（5原則準拠、workerプロンプト品質、問題解決確認）

## 手順

### 1. 構造検証（validate 相当）
```bash
cd {plugin-path}
twl check
twl validate
```

### 2. 5原則準拠チェック
ref-practices を参照して、全コンポーネントが5原則に準拠しているか確認。

特に team-worker ファイルを重点的にチェック:
- 完結: 目的・制約・報告方法が明記されている
- 明示: 型・ツール制約が冒頭宣言されている
- 外部化: per_phase時の外部コンテキスト手段がある
- 並列安全: ファイル競合リスクがない
- コスト意識: model・turn数が明示されている

### 3. 修正前後の差分表示
```bash
cd {plugin-path} && git diff
```

### 4. ユーザー確認
検証結果を表示し、ユーザーに確認:
- 全チェック通過 → 完了
- 問題あり → fix に戻る提案

## Context Snapshot（controller-improve 経由の場合）
controller-improve から呼ばれる場合、phase-verify が並列実行を担当するため、
このコマンドは standalone（単体）での使用向け。
standalone 使用時も、snapshot_dir が指定されている場合は結果を
`{snapshot_dir}/05-verify-results.md` に Write する。

## 出力
検証結果サマリー:
- 構造検証: OK/NG
- 5原則チェック: 各原則のスコア
- 総合判定: PASS/FAIL
