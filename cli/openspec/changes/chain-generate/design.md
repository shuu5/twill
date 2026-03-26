## Context

loom-engine.py は argparse ベースの CLI ツールで、`--check`, `--validate`, `--rename` 等のフラグ/サブコマンドで deps.yaml を操作する。v3.0 で `chains`/`step`/`step_in` フィールドが導入され、`chain_validate()` で双方向整合性検証が実装済み。

chains 構造:
```yaml
chains:
  chain-name:
    type: A | B
    steps: [comp1, comp2, comp3]
```

コンポーネント側:
```yaml
skills:
  comp1:
    chain: chain-name
    step_in:
      parent: parent-comp
      step: "2.3"
    calls:
      - workflow: comp2
        step: "3"
```

## Goals / Non-Goals

**Goals:**

- deps.yaml の chains 情報から 3 種類のテンプレートを自動生成する `chain generate` サブコマンドを追加
- Template A（チェックポイント）: Chain 参加者ごとに next コンポーネントを解決し出力
- Template B（called-by）: step_in を持つコンポーネントの呼び出し元宣言を生成
- Template C（ライフサイクル図）: chain の全 step をテーブル形式で生成
- `--write` フラグでプロンプトファイルへの直接書き込み

**Non-Goals:**

- deps.yaml スキーマ自体の変更（#11 スコープ）
- 双方向整合性検証の追加（#12 で実装済み）
- dev plugin プロンプトへの --write 実適用（--auto 廃止後の別 Issue）
- rename 時の chain 更新（#5 スコープ）

## Decisions

1. **サブコマンド形式**: `--chain-generate <chain-name>` ではなく、positional 引数で `chain generate <chain-name>` とする。ただし、現在の argparse 構造はフラットなフラグベースのため、`chain` を第一引数として分岐し、`generate` をサブアクションとして処理する。実装は `sys.argv` を先に検査して chain サブコマンドを検出し、専用の argparse を使う。

2. **テンプレート出力形式**: 各テンプレートをセクション区切り付きで stdout に出力。`--- Template A: <comp-name> ---` 形式のヘッダーで区分。

3. **--write の置換パターン**: プロンプトファイル内の既存セクションを以下のマーカーで検出:
   - Template A: `## チェックポイント` または `## Checkpoint` セクション
   - Template B: frontmatter の description 内 `から呼び出される` パターン
   - Template C: `## ライフサイクル` または `## Lifecycle` セクション
   マーカー未検出時は警告を出力し、スキップ。

4. **chain type による分岐**: Chain A（workflow chain）は Template A + C を生成。Chain B（composite chain）は Template B を生成。chain type が未指定の場合は全テンプレートを生成。

5. **v3.0 以外はエラー**: deps.yaml version が 3.x 未満の場合はエラーメッセージを出力して終了。

## Risks / Trade-offs

- **--write のパターンマッチ精度**: セクションヘッダーの表記ゆれ（日本語/英語）により検出漏れの可能性。初期実装では厳密なマーカーベースとし、検出失敗時は警告で対応。
- **chain type 未設定の deps.yaml**: type フィールドがオプショナルな場合、全テンプレートが生成される。意図しない出力が発生する可能性があるが、--write なしの stdout 出力であれば安全。
- **サブコマンド方式の argparse 互換性**: 既存のフラグベース CLI に positional サブコマンドを追加するため、`sys.argv` 前処理が必要。将来的に argparse subparsers への移行を検討。
