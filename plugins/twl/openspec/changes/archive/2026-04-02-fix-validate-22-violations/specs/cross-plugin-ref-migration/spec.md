## MODIFIED Requirements

### Requirement: external 依存を cross-plugin 参照に移行

4 コンポーネント（autopilot-poll, autopilot-phase-execute, crash-detect, health-check）の calls から `external`/`path`/`optional`/`note` キーを除去し、`script: session:session-state` 形式の cross-plugin 参照に置換しなければならない（SHALL）。

#### Scenario: autopilot-poll の calls 修正
- **WHEN** autopilot-poll の calls に `external: session-state.sh` エントリが存在する
- **THEN** 当該エントリを `- script: session:session-state` に置換し、`path`/`optional`/`note` キーを除去する

#### Scenario: autopilot-phase-execute の calls 修正
- **WHEN** autopilot-phase-execute の calls に `external: session-state.sh` エントリが存在する
- **THEN** 当該エントリを `- script: session:session-state` に置換し、`path`/`optional`/`note` キーを除去する

#### Scenario: crash-detect の calls 修正
- **WHEN** crash-detect の calls に `external: session-state.sh` エントリが存在する
- **THEN** 当該エントリを `- script: session:session-state` に置換し、`path`/`optional`/`note` キーを除去する

#### Scenario: health-check の calls 修正
- **WHEN** health-check の calls に `external: session-state.sh` エントリが存在する
- **THEN** 当該エントリを `- script: session:session-state` に置換し、`path`/`optional`/`note` キーを除去する

### Requirement: loom validate が Violations 0 で PASS

修正後、`loom validate` が Violations 0 で exit code 0 を返さなければならない（MUST）。

#### Scenario: validate 全件 PASS
- **WHEN** deps.yaml 修正後に `loom validate` を実行する
- **THEN** Violations: 0 が出力され、exit code 0 で終了する

### Requirement: loom check が Missing 0 を維持

修正後、`loom check` が Missing 0 を維持しなければならない（MUST）。

#### Scenario: check 全件 PASS
- **WHEN** deps.yaml 修正後に `loom check` を実行する
- **THEN** Missing: 0 が出力される
