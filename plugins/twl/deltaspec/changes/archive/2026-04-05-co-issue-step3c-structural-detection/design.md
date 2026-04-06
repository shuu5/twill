## Context

co-issue SKILL.md Step 3c の「出力なし完了の検知（上位ガード）」は、specialist の返却値に `status:` または `findings:` キーワードが含まれない場合を「出力なし完了」と判定する。この判定は単純な文字列検索であり、`message: "status: PASS"` や `"status: ok"` のような非構造化テキストに偶然キーワードが含まれると誤って「出力あり」と判定してしまう。

`refs/ref-specialist-output-schema.md` L151 の消費側パースルールも `status: (PASS|WARN|FAIL)` で行頭縛りがない。co-issue 独自の上位ガードとして行頭縛りを追加適用することで、より厳格な検知を行う。

## Goals / Non-Goals

**Goals:**

- Step 3c 前処理の status 検出を `^status:\s*(PASS|WARN|FAIL)` に変更（行頭縛り・有効値のみ）
- findings 検出を `^findings:` に変更（行頭縛り）
- ref との関係を SKILL.md に注記

**Non-Goals:**

- `refs/ref-specialist-output-schema.md` 自体の変更
- specialist agent 側の出力フォーマット変更
- deps.yaml の変更（コンポーネント追加なし）

## Decisions

**行頭縛り正規表現の採用**:
- `status:` キーワードが文中に含まれる誤検知を防ぐために `^` アンカーを使用
- 有効値（PASS/WARN/FAIL）のみをマッチ対象とすることで、`status: ok` 等の非規格値による誤検知も排除
- findings についても同様に `^findings:` で行頭縛り

**ref との関係記述**:
- ref-specialist-output-schema.md L151 の regex には行頭縛りがない（下位ガード）
- co-issue Step 3c のガードを「上位ガード」として位置付け、SKILL.md に注記を追加
- ref 自体は変更しない（影響範囲を最小化）

## Risks / Trade-offs

- **リスクなし**: 正規表現のパターンはより厳格になるため、既存の正常な specialist 出力（`status: PASS` が行頭にある）には影響なし。行頭に出力しない specialist があれば WARNING になるが、それは正しい検知
