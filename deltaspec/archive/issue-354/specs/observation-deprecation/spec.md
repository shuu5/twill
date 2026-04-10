## MODIFIED Requirements

### Requirement: OBS-* セクションの deprecation 注記追加

observation.md の Observer Constraints (OBS-*) セクションの先頭に、SU-* への移行を示す deprecation 注記を追加しなければならない（SHALL）。
注記は blockquote 形式で「Superseded: OBS-1〜OBS-5 は supervision.md の SU-1〜SU-7 に統合されました（ADR-014）。」を含まなければならない（SHALL）。

#### Scenario: OBS-* セクションの deprecation 表示

- **WHEN** observation.md の OBS-* Constraints セクションを参照したとき
- **THEN** セクション先頭に `> **Superseded**: OBS-1〜OBS-5 は supervision.md の SU-1〜SU-7 に統合されました（ADR-014）。` の blockquote が表示される

### Requirement: OB-3 注記の ADR-014 参照更新

observation.md の OB-3 適用範囲注記を更新しなければならない（SHALL）。
旧 ADR-013 / co-observer / OBS-* の参照を ADR-014 / su-observer / SU-7 に差し替えなければならない（SHALL）。

#### Scenario: OB-3 注記の正確な参照

- **WHEN** observation.md の OB-3 適用範囲注記を参照したとき
- **THEN** 「su-observer は介入権限を持つ Supervisor レイヤー（ADR-014）のため OB-3 適用外。介入ルールは SU-7 で定義（supervision.md）。」と記述されている

## REMOVED Requirements

### Requirement: Component Mapping から co-observer 行を削除

observation.md の Component Mapping テーブルから co-observer 行を削除しなければならない（SHALL）。
supervision.md に su-observer として移動済みであるため、observation.md への重複記載は許容されない（MUST NOT）。

#### Scenario: Component Mapping に co-observer が含まれない

- **WHEN** observation.md の Component Mapping テーブルを参照したとき
- **THEN** co-observer の行が存在しない
