## ADDED Requirements

### Requirement: glossary 照合ステップ（co-issue Step 1.5）

co-issue の Phase 1 完了後（explore-summary.md 生成後）に、`architecture/domain/glossary.md` の MUST 用語と explore-summary.md の主要用語を照合するステップを挿入しなければならない（SHALL）。

照合は以下の条件で実行される:
- `architecture/domain/glossary.md` が存在する場合のみ実行する（SHALL）
- 存在しない場合は Step 1.5 をスキップし、次の Phase 2 に進む（SHALL）
- 完全一致しない用語が 1 件以上あれば、INFO レベルで通知する（SHALL）
- 通知メッセージは「この概念は architecture spec に未定義です: [用語リスト]」の形式にしなければならない（SHALL）
- 通知はフロー停止せず、Phase 2 に継続する（SHALL）

#### Scenario: glossary に存在しない用語が発見される
- **WHEN** explore-summary.md に「quick-issue」という用語が含まれ、architecture/domain/glossary.md の MUST 用語に「quick-issue」が存在しない
- **THEN** INFO レベルで「この概念は architecture spec に未定義です: quick-issue」と通知し、Phase 2 に継続する

#### Scenario: architecture/ が存在しない
- **WHEN** プロジェクトに `architecture/` ディレクトリが存在しない
- **THEN** Step 1.5 をスキップし、メッセージを出力せずに Phase 2 に継続する

#### Scenario: 全用語が glossary に存在する
- **WHEN** explore-summary.md の全主要用語が architecture/domain/glossary.md の MUST 用語と一致する
- **THEN** 通知を出力せずに Phase 2 に継続する
