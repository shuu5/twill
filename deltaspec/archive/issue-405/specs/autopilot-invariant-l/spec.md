## ADDED Requirements

### Requirement: 不変条件 L — autopilot マージ実行責務の明文化

autopilot.md の Constraints セクションに不変条件 L を追加しなければならない（SHALL）。不変条件 L は「autopilot 時のマージ実行は Orchestrator の mergegate.py 経由のみ。Worker chain の auto-merge ステップは merge-ready 宣言のみを行い、マージは実行しない」と明記されなければならない（SHALL）。

#### Scenario: autopilot.md に不変条件 L が存在する
- **WHEN** `architecture/autopilot.md` の Constraints セクションを参照する
- **THEN** 不変条件 L として「autopilot 時のマージ実行は Orchestrator の mergegate.py 経由のみ」が記載されている

#### Scenario: Worker chain の auto-merge 責務が明示されている
- **WHEN** autopilot.md の不変条件 L を参照する
- **THEN** 「Worker chain の auto-merge ステップは merge-ready 宣言のみを行い、マージは実行しない」と明記されている

## MODIFIED Requirements

### Requirement: autopilot-orchestrator.sh fallback パスのコメント修正

autopilot-orchestrator.sh の fallback パス（line 868 付近）のコメントは実態（`return 1` のみで auto-merge.sh を呼び出さない）に合わせて修正しなければならない（SHALL）。誤解を招く「auto-merge.sh にフォールバック」という表現を削除または修正しなければならない（MUST）。

#### Scenario: fallback パスのコメントが実態に即している
- **WHEN** `plugins/twl/scripts/autopilot-orchestrator.sh` の fallback パス（line 868 付近）を参照する
- **THEN** コメントが「実際は return 1 のみ（auto-merge.sh は呼び出さない）」など実態を正確に反映している

#### Scenario: auto-merge.sh、mergegate.py、chain-runner.sh が変更されていない
- **WHEN** `git diff` で変更ファイルを確認する
- **THEN** `auto-merge.sh`、`mergegate.py`、`chain-runner.sh` のいずれにも変更が含まれていない
