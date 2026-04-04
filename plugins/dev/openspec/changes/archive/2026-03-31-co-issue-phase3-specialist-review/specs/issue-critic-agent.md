## ADDED Requirements

### Requirement: issue-critic agent 作成

issue-critic agent は、構造化された Issue body を受け取り、仮定・曖昧点・盲点・粒度・split 提案・隠れた依存を検出しなければならない（SHALL）。Agent tool によるコンテキスト非継承 spawn で実行され、co-issue セッションの会話コンテキストを参照してはならない（MUST NOT）。

出力は ADR-004 findings 形式に準拠しなければならない（SHALL）。category は `assumption`, `ambiguity`, `scope` のいずれかを使用する。

agent frontmatter: `model: sonnet`, `maxTurns: 15`

#### Scenario: 曖昧な受け入れ基準の検出
- **WHEN** Issue body の受け入れ基準に「適切に動作する」等の定量化されていない記述が含まれる
- **THEN** severity: WARNING, category: ambiguity の finding を出力する

#### Scenario: 未検証の仮定の検出
- **WHEN** Issue body が前提条件を暗黙に仮定している（例: 特定の API が存在する、特定のスキーマが変更されない）
- **THEN** severity: WARNING, category: assumption の finding を出力する

#### Scenario: 粒度過大による split 提案
- **WHEN** Issue のスコープが複数の独立した関心事を含み、推定変更ファイル数が 10 を超える
- **THEN** severity: CRITICAL, category: scope の finding を出力し、具体的な split 候補を message に含める

#### Scenario: 隠れた依存の検出
- **WHEN** Issue body に明示されていない他 Issue/コンポーネントへの依存が実コードから検出される
- **THEN** severity: WARNING, category: assumption の finding を出力する

#### Scenario: 問題なしの場合
- **WHEN** 全検出観点で問題が見つからない
- **THEN** status: PASS, findings: [] を出力する
