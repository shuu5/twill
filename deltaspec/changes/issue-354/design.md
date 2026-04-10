## Context

ADR-014 Decision 5 で co-observer が su-observer に昇格。OBS-1〜OBS-5 は SU-1〜SU-7 に統合済み（supervision.md に記述）。
observation.md は旧 Observer Context（ADR-013）の定義を残したままであり、現行アーキテクチャとの乖離がある。

対象ファイル: `plugins/twl/architecture/domain/contexts/observation.md`

## Goals / Non-Goals

**Goals:**
- observation.md の OBS-* Constraints セクションに deprecation 注記を追加し、supervision.md の SU-* への移行を明示する
- Component Mapping から co-observer 行を削除（supervision.md 側に移動済みのため重複排除）
- OB-3 適用範囲注記を ADR-014 / SU-* の参照に更新し、co-observer → su-observer の変更を反映

**Non-Goals:**
- supervision.md の変更（SU-1〜SU-7 は確認済みで変更不要）
- コードや CLI の変更
- OBS-* セクション自体の完全削除（deprecation 注記として残す方針）

## Decisions

1. **OBS-* セクションは削除せず非推奨化する**
   - 理由: 突然削除すると既存ドキュメント参照が壊れるリスクがある。`> **Superseded**: OBS-1〜OBS-5 は supervision.md の SU-1〜SU-7 に統合されました（ADR-014）。` の blockquote 注記を追加する。

2. **co-observer Component Mapping 行は削除する**
   - 理由: supervision.md の Component Mapping にすでに su-observer が定義されており、observation.md に co-observer を残すと「observation の責務コンポーネント」として誤解される。

3. **OB-3 注記は SU-7 参照に更新する**
   - 現行: 「co-observer は介入権限を持つメタ認知レイヤー（ADR-013）のため OB-3 適用外。介入ルールは OBS-1〜OBS-5 で定義。」
   - 更新後: 「su-observer は介入権限を持つ Supervisor レイヤー（ADR-014）のため OB-3 適用外。介入ルールは SU-7 で定義（supervision.md）。」

## Risks / Trade-offs

- **リスク**: OBS-* セクションを残すことで「まだ有効な制約」と誤認される可能性がある。
  - 緩和: blockquote の Superseded 注記を先頭に目立つ形で追加する。
- **トレードオフ**: セクション削除 vs 注記残存。削除はシンプルだが検索可能性・移行経緯の追跡性が失われる。今回は注記残存を選択。
