## MODIFIED Requirements

### Requirement: classify_layers の再帰的 sub-command 走査

`classify_layers()` は L1（direct_commands）から到達可能な全深度の commands を `sub_commands` に分類しなければならない（MUST）。L1→L2 の 1 段走査ではなく、任意深度のチェーンを走査する。

#### Scenario: L2 コマンドがさらに commands を呼ぶ（L3）
- **WHEN** L1 コマンドが L2 コマンドを calls で呼び、L2 コマンドがさらに L3 コマンドを calls で呼ぶ
- **THEN** L3 コマンドも `sub_commands` に分類され、`orphan_commands` には含まれない

#### Scenario: 3 段以上のチェーン
- **WHEN** cmd-a → cmd-b → cmd-c → cmd-d の 4 段チェーンが存在する
- **THEN** cmd-b, cmd-c, cmd-d が全て `sub_commands` に分類される

#### Scenario: 循環呼び出し
- **WHEN** cmd-a → cmd-b → cmd-a の循環チェーンが存在する
- **THEN** 無限ループせず正常に完了し、両方が `sub_commands` に分類される
