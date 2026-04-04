## ADDED Requirements

### Requirement: Issue 品質基準リファレンス作成

ref-issue-quality-criteria は、issue-critic および issue-feasibility specialist に注入される Issue 品質基準を定義しなければならない（SHALL）。specialist の agent frontmatter `skills` フィールドで参照される。

#### Scenario: specialist への品質基準注入
- **WHEN** issue-critic または issue-feasibility が Agent tool で spawn される
- **THEN** ref-issue-quality-criteria の内容が specialist のコンテキストに含まれる

#### Scenario: severity 判定基準の明示
- **WHEN** specialist が finding の severity を判定する
- **THEN** ref-issue-quality-criteria に定義された基準に従い、CRITICAL / WARNING / INFO を割り当てなければならない（MUST）

#### Scenario: 過剰 CRITICAL の防止
- **WHEN** 軽微な記述の曖昧さ（例: 「適切に」程度の表現）が検出される
- **THEN** severity は WARNING とし、CRITICAL にしてはならない（MUST NOT）。CRITICAL は Phase 4 進行をブロックするため、真に重大な問題（スコープ不明、対象ファイル不在、粒度過大）にのみ使用する
