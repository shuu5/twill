## MODIFIED Requirements

### Requirement: SKILL.md spawn prompt MUST NOT サブ節追加

`plugins/twl/skills/su-observer/SKILL.md` の「spawn プロンプトの文脈包含」節（L331-338）に `#### MUST NOT: skill 自律取得可能情報の転記` サブ節が追加されなければならない（SHALL）。サブ節には Issue body・comments・explore summary・architecture・Phase 手順・past memory 生データ・bare repo/worktree 構造の列挙を含む。

#### Scenario: MUST NOT サブ節が存在する
- **WHEN** `SKILL.md` の「spawn プロンプトの文脈包含」節を参照する
- **THEN** `#### MUST NOT: skill 自律取得可能情報の転記` ヘッダーが存在し、7 項目以上の列挙がある

### Requirement: SKILL.md 最小 prompt 例の追加

`SKILL.md` に co-issue refine 向けの最小 prompt 例（5-10 行型テンプレ）が追加されなければならない（SHALL）。テンプレは §10 MUST 5 項目を網羅する。

#### Scenario: 最小 prompt 例が MUST 5 項目を含む
- **WHEN** `SKILL.md` の最小 prompt 例を参照する
- **THEN** spawn 元識別・Issue 番号・proxy 対話期待・observer 独自観点・Wave 文脈の 5 要素が含まれる

#### Scenario: 最小 prompt 例が 5-10 行に収まる
- **WHEN** `SKILL.md` の最小 prompt 例テンプレを参照する
- **THEN** 例示行数が 10 行以内に収まっている
