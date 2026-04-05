## MODIFIED Requirements

### Requirement: CHAIN_STOP_PATTERNS → 次コマンドマッピング定義

`autopilot-orchestrator.sh` は `CHAIN_STOP_PATTERNS` を停止パターンをキー、次コマンドを値とする連想配列として定義しなければならない（SHALL）。全5パターンに対してマッピングを定義しなければならない（SHALL）。

| パターン | 次コマンド |
|---------|-----------|
| `setup chain 完了` | `/twl:workflow-test-ready #N` |
| `>>> 提案完了` | 空（chain 内遷移） |
| `テスト準備.*完了` | `/twl:workflow-pr-cycle #N` |
| `PR サイクル.*完了` | 空（chain 終端） |
| `workflow-test-ready.*で次に進めます` | `/twl:workflow-test-ready #N` |

#### Scenario: setup chain 完了パターン検知時の nudge 送信
- **WHEN** tmux 出力に "setup chain 完了" が含まれており、出力ハッシュが変化していない
- **THEN** `/twl:workflow-test-ready #N` が Worker プロンプトに送信される（N は issue 番号）

#### Scenario: テスト準備完了パターン検知時の nudge 送信
- **WHEN** tmux 出力に "テスト準備.*完了" が含まれており、出力ハッシュが変化していない
- **THEN** `/twl:workflow-pr-cycle #N` が Worker プロンプトに送信される（N は issue 番号）

#### Scenario: chain 内遷移パターン（提案完了）の空 Enter 送信
- **WHEN** tmux 出力に ">>> 提案完了" が含まれており、出力ハッシュが変化していない
- **THEN** 空 Enter が送信される（SKILL.md が chain を継続するため次コマンド不要）

#### Scenario: chain 終端パターン（PR サイクル完了）の空 Enter 送信
- **WHEN** tmux 出力に "PR サイクル.*完了" が含まれており、出力ハッシュが変化していない
- **THEN** 空 Enter が送信される（chain 終端のため次コマンド不要）

### Requirement: issue 番号を nudge コマンドに埋め込む

`check_and_nudge()` は次コマンドに `#N` プレースホルダーが含まれる場合、既存引数 `$issue` の値で置換したコマンドを送信しなければならない（SHALL）。

#### Scenario: issue 番号の置換
- **WHEN** 次コマンドが `/twl:workflow-test-ready #N` であり、issue=129
- **THEN** `/twl:workflow-test-ready #129` が Worker プロンプトに送信される

### Requirement: nudge 上限カウントの維持

`check_and_nudge()` は nudge 上限（MAX_NUDGE）のカウントを Issue 単位で維持しなければならない（SHALL）。nudge コマンドの種類（空 Enter か Skill コマンドか）に関わらず、送信のたびにカウントをインクリメントしなければならない（SHALL）。

#### Scenario: nudge 上限到達時の送信停止
- **WHEN** `NUDGE_COUNTS[$issue]` が `MAX_NUDGE` 以上
- **THEN** nudge は送信されない（コマンド種別によらず既存の上限チェックが適用される）
