## 1. Vision 精緻化

- [x] 1.1 vision.md に「機械 vs LLM」の判断境界テーブルを追加（機械: 状態管理・バリデーション・シーケンシング / LLM: レビュー品質・エラー診断・設計判断）
- [x] 1.2 vision.md Constraints に旧 plugin 複雑性ホットスポット回避策を明記（9 controller → 4, 6種マーカー → 統一状態ファイル, --auto/--auto-merge → autopilot-first）
- [x] 1.3 vision.md Non-Goals に「技術スタック固有機能はコンパニオンプラグインの責務」を展開

## 2. Domain Model 精緻化

- [x] 2.1 model.md に Controller 4つの spawning 関係 Mermaid 図を追加（co-autopilot → composite/atomic/specialist, co-issue → composite/atomic/reference, co-project → atomic, co-architect → atomic/reference）
- [x] 2.2 model.md に issue-{N}.json と session.json のフィールド一覧テーブルを追加
- [x] 2.3 model.md に Chain 定義と実行フローの関係 Mermaid 図を追加

## 3. Glossary 精緻化

- [x] 3.1 glossary.md に旧→新用語対応表（Markdown テーブル）を追加
- [x] 3.2 glossary.md に「廃止」セクションを追加（--auto, --auto-merge, 6種マーカー, direct パス, 9種 controller）

## 4. Contexts 精緻化

- [x] 4.1 autopilot.md に Key Entities 列挙と controller/workflow/command マッピングテーブルを追加
- [x] 4.2 pr-cycle.md に Key Entities 列挙と controller/workflow/command マッピングテーブルを追加
- [x] 4.3 issue-mgmt.md に Key Entities 列挙と controller/workflow/command マッピングテーブルを追加
- [x] 4.4 project-mgmt.md に Key Entities 列挙と controller/workflow/command マッピングテーブルを追加
- [x] 4.5 self-improve.md に Key Entities 列挙と controller/workflow/command マッピングテーブルを追加
- [x] 4.6 loom-integration.md に loom CLI コマンドと plugin コンポーネントの対応表を拡充

## 5. Phases 精緻化

- [x] 5.1 phases/01.md に Issue 間依存関係を完全記載（loom#31, loom#28 等の外部依存含む）
- [x] 5.2 phases/01.md に Implementation Status 列を追加
- [x] 5.3 phases/02.md に Issue 間依存関係を完全記載
- [x] 5.4 phases/02.md に Implementation Status 列を追加

## 6. 検証

- [x] 6.1 全ファイルの自己完結性を確認（各ファイルが単独で仕様書として読める）
- [x] 6.2 B-1 (#3) の設計判断14項が適切な場所に反映されていることを確認
