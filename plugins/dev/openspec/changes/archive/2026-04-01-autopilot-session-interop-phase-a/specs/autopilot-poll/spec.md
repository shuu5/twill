## MODIFIED Requirements

### Requirement: autopilot-poll session-state.sh wait 活用

autopilot-poll は session-state.sh が利用可能な場合、`session-state.sh wait` を活用してポーリング効率を改善しなければならない（SHALL）。session-state.sh 非存在時は既存の sleep 10 ループを維持しなければならない（MUST）。

#### Scenario: session-state.sh 利用可能時のポーリング
- **WHEN** session-state.sh が利用可能で Worker が running 状態
- **THEN** `session-state.sh wait <window> exited --timeout 10` と `session-state.sh state <window>` の組み合わせでポーリングし、crash-detect.sh に状態チェックを委譲する

#### Scenario: session-state.sh 非存在時のポーリング
- **WHEN** session-state.sh が利用不可
- **THEN** 従来の sleep 10 + state-read.sh + crash-detect.sh ループを維持する

### Requirement: autopilot-poll タイムアウト維持

session-state.sh 活用時も MAX_POLL ベースのタイムアウト（60 分）は維持しなければならない（MUST）。

#### Scenario: タイムアウト到達
- **WHEN** session-state.sh 利用時にポーリング経過時間が MAX_POLL（60 分）を超過する
- **THEN** 従来と同様に未完了 Issue を failed に遷移する

## MODIFIED Requirements

### Requirement: deps.yaml 外部依存明示

deps.yaml の autopilot-poll エントリの calls セクションに session-state.sh の外部依存を明示しなければならない（SHALL）。

#### Scenario: deps.yaml 更新
- **WHEN** autopilot-poll の依存関係を参照する
- **THEN** session-state.sh が外部依存として calls セクションに記載されている

## MODIFIED Requirements

### Requirement: co-autopilot SKILL.md 記述更新

skills/co-autopilot/SKILL.md の crash-detect.sh に関する記述を session-state.sh 統合後の動作に更新しなければならない（SHALL）。

#### Scenario: SKILL.md の crash-detect 記述
- **WHEN** co-autopilot の SKILL.md を参照する
- **THEN** crash-detect.sh が session-state.sh を利用する旨と、フォールバック動作の記述が含まれている
