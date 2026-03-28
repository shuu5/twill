## ADDED Requirements

### Requirement: co-issue SKILL.md 4 Phase フロー実装

co-issue の SKILL.md を stub から完全実装に置き換えなければならない（MUST）。architecture/domain/contexts/issue-mgmt.md の設計定義に準拠し、旧 controller-issue の 4 Phase ワークフローを移植する。

SKILL.md は以下の Phase 構成を持たなければならない（SHALL）:

- Phase 1: 問題探索（/dev:explore 呼び出し、explore-summary.md 保存）
- Phase 2: 分解判断（単一 vs 複数 Issue の判定）
- Phase 3: Per-Issue 精緻化ループ（issue-dig → issue-structure → issue-assess → issue-tech-debt-absorb）
- Phase 4: 一括作成（ユーザー確認 → issue-create/issue-bulk-create → project-board-sync）

#### Scenario: 単一 Issue 作成
- **WHEN** ユーザーが要望を伝え、分解判断で単一 Issue と判定される
- **THEN** Phase 3 で 1 件の精緻化を実行し、Phase 4 で issue-create が呼ばれる

#### Scenario: 複数 Issue 分解
- **WHEN** 分解判断で複数 Issue が必要と判定される
- **THEN** Phase 3 で各候補に対して精緻化ループが実行され、Phase 4 で issue-bulk-create が呼ばれる

### Requirement: explore-summary 検出による Phase 1 スキップ

co-issue は起動時に `.controller-issue/explore-summary.md` の存在を確認しなければならない（MUST）。存在する場合、ユーザーに継続/最初からの選択を提示しなければならない（SHALL）。

#### Scenario: explore-summary が存在する場合
- **WHEN** `.controller-issue/explore-summary.md` が存在する
- **THEN** AskUserQuestion で「継続する / 最初から」の選択肢が提示され、「継続」選択時は Phase 2 から開始される

#### Scenario: explore-summary が存在しない場合
- **WHEN** `.controller-issue/explore-summary.md` が存在しない
- **THEN** 通常の Phase 1（問題探索）から開始される

### Requirement: TaskCreate による Phase 進捗管理

co-issue は各 Phase 開始時に TaskCreate でタスクを登録し、Phase 完了時に TaskUpdate で completed に更新しなければならない（MUST）。

#### Scenario: 4 Phase の進捗追跡
- **WHEN** co-issue が起動される
- **THEN** Phase 1〜4 のタスクが順次登録・更新され、ユーザーが CLI 上で進捗を確認できる

### Requirement: Phase 4 完了後のクリーンアップ

co-issue は Phase 4 完了後に `.controller-issue/` ディレクトリを削除しなければならない（MUST）。Issue URL を表示し、`/dev:workflow-setup #N` を案内しなければならない（SHALL）。

#### Scenario: Issue 作成完了
- **WHEN** Phase 4 で Issue 作成が成功する
- **THEN** `.controller-issue/` が削除され、作成された Issue の URL と次のステップが表示される
