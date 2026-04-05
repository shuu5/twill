## Why

co-issue SKILL.md Step 3c の「出力なし完了の検知」は `status:` / `findings:` キーワードの存在チェックのみで判定しており、非構造化テキスト中にこれらの文字列が偶然含まれるケースで誤判定（偽陰性）が発生する。行頭縛りの正規表現に変更することで誤検知を排除する。

## What Changes

- `skills/co-issue/SKILL.md` Step 3c の「出力なし完了の検知」ロジックを以下の正規表現ベースの上位ガードに置き換え:
  - status 検出: `^status:\s*(PASS|WARN|FAIL)` （行頭・有効値のみ）
  - findings 検出: `^findings:` （行頭）
- `ref-specialist-output-schema.md` との関係を SKILL.md Step 3c に注記（ref 自体は変更しない）

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `co-issue Step 3c 出力なし検知ガード`: キーワード有無チェックから行頭縛り正規表現に変更。`message: "status: PASS"` や文中の `status: ok` で誤検知しなくなる

## Impact

- **変更ファイル**: `skills/co-issue/SKILL.md`（Step 3c 前処理セクション、約 L185 付近）
- **影響範囲**: co-issue Step 3c のみ。specialist agent 側の出力フォーマットには影響なし
- **依存**: `refs/ref-specialist-output-schema.md`（参照のみ、変更なし）
