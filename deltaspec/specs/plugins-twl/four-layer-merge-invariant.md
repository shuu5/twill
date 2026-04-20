## Requirements

### Requirement: 4 層防御による不変条件 C の強制

Worker が直接マージを実行できないよう、4 層の独立した防御メカニズムが存在しなければならない（SHALL）。

#### Scenario: chain-runner ガードによるマージブロック
- **WHEN** Worker が `chain-runner.sh` 経由で `gh pr merge` を実行しようとする
- **THEN** `chain-runner.sh` の guard がブロックし、`"gh pr merge は禁止されています"` に相当するエラーが返される

#### Scenario: auto-merge.sh ガードによるマージブロック
- **WHEN** Worker が `auto-merge.sh` を直接呼び出す
- **THEN** `auto-merge.sh` の呼び出し元チェックが Worker からの呼び出しを拒否する

#### Scenario: PreToolUse hook によるマージブロック
- **WHEN** Worker セッションで `gh pr merge` コマンドを含む Bash ツール呼び出しが発生する
- **THEN** Claude Code の PreToolUse hook が呼び出しをブロックする

#### Scenario: SKILL.md の不変条件 C 注記
- **WHEN** Worker が SKILL.md を参照する
- **THEN** 不変条件 C（`gh pr merge` 直接実行禁止、マージ権限は Pilot のみ）が明記されており、chain-runner.sh auto-merge 経由でのみマージが許可される旨が記載されている

### Requirement: 4 層防御は独立して動作する

各防御層は他の層に依存せず独立して機能しなければならない（MUST）。いずれか 1 層が欠落しても残りの層がマージを防止できる。

#### Scenario: 任意の 1 層が欠落しても防御が維持される
- **WHEN** 4 層のうち任意の 1 層が一時的に無効化される
- **THEN** 残りの 3 層がマージブロック機能を維持する

### Requirement: chain-runner.sh 経由の auto-merge のみ許可

Pilot が squash merge を実行する場合、必ず `chain-runner.sh auto-merge` 経由で `auto-merge.sh` のガードを通さなければならない（SHALL）。

#### Scenario: 正常な merge フロー
- **WHEN** merge-gate が PASS を返す
- **THEN** `chain-runner.sh auto-merge` → `auto-merge.sh` の順で squash merge が実行される
- **AND** `gh pr merge` の直接呼び出しは使用されない
