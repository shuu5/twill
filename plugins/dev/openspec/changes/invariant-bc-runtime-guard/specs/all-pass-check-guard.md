## MODIFIED Requirements

### Requirement: all-pass-check autopilot 配下 merge-ready 遷移

all-pass-check.md は state-write.sh を正しい named-argument 形式で呼び出さなければならない（MUST）。autopilot 配下では Worker ロールで merge-ready に遷移しなければならない（SHALL）。

#### Scenario: 全テスト PASS 時の state-write（autopilot 配下）
- **WHEN** 全ステップが PASS/WARN で autopilot 配下（status=running）である
- **THEN** `state-write.sh --type issue --issue "$ISSUE_NUM" --role worker --set "status=merge-ready"` を実行する

#### Scenario: 全テスト PASS 時の state-write（非 autopilot）
- **WHEN** 全ステップが PASS/WARN で autopilot 配下でない
- **THEN** 既存動作を維持する（merge-gate へ遷移）

#### Scenario: テスト FAIL 時の state-write
- **WHEN** いずれかのステップが FAIL（CRITICAL あり）
- **THEN** `state-write.sh --type issue --issue "$ISSUE_NUM" --role worker --set "status=failed"` を実行する

#### Scenario: state-write 構文の正確性
- **WHEN** state-write.sh が呼び出される
- **THEN** 旧形式（位置引数）ではなく named-argument 形式（`--type`, `--issue`, `--role`, `--set`）を使用しなければならない（MUST）
