## MODIFIED Requirements

### Requirement: su-observer-skill-design.md のモードルーティングテーブル廃止

su-observer-skill-design.md のモードルーティングテーブル（6 モード: autopilot, issue, architect, observe, compact, delegate）を削除しなければならない（SHALL）。代わりに行動判断ガイドラインを設けなければならない（SHALL）。

#### Scenario: 行動判断ガイドラインへの置換
- **WHEN** su-observer-skill-design.md を参照する LLM が行動を決定する
- **THEN** モード番号ではなく、文脈に基づく行動判断ガイドラインから適切なアクションを選択しなければならない（SHALL）

### Requirement: su-observer-skill-design.md のステップ構造簡素化

su-observer-skill-design.md のステップ構造を SKILL.md に合わせて「Step 0 初期化 / Step 1 常駐ループ / Step 2 終了」の 3 ステップに統一しなければならない（SHALL）。

#### Scenario: 設計ドキュメントと SKILL.md の整合
- **WHEN** 設計ドキュメントを参照して SKILL.md の動作を理解しようとする
- **THEN** 両ドキュメントのステップ構造が一致しており、モードの乖離がないことが確認できなければならない（SHALL）

### Requirement: supervision.md の「モード」言及削除

supervision.md のワークフロー図に「モード」という単語が残存してはならない（SHALL NOT）。分岐ラベル（「autopilot 指示」等）は LLM の文脈判断の例示として維持してよい（MAY）。

#### Scenario: supervision.md のワークフロー図確認
- **WHEN** supervision.md の flowchart を確認する
- **THEN** 「モード」という文字列が存在してはならない（SHALL NOT）。分岐ラベルは「指示」や「判断」の例示として記述されていなければならない（SHALL）
