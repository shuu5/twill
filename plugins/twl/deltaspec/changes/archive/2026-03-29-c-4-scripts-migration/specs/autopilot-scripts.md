## ADDED Requirements

### Requirement: autopilot-plan スクリプト移植

autopilot-plan.sh を新リポジトリの `scripts/` に移植し、plan.yaml 出力先を `.autopilot/` 配下に変更しなければならない（SHALL）。`--explicit` と `--issues` の2モードを維持し、deps.yaml 競合検出ロジックも保持する。

#### Scenario: explicit モードで plan.yaml 生成
- **WHEN** `bash scripts/autopilot-plan.sh --explicit "19,18 → 20 → 23" --project-dir $PWD --repo-mode worktree` を実行する
- **THEN** `.autopilot/plan.yaml` に session_id, repo_mode, project_dir, phases, dependencies が出力される

#### Scenario: issues モードで依存グラフから Phase 分割
- **WHEN** `bash scripts/autopilot-plan.sh --issues "10 11 12" --project-dir $PWD --repo-mode worktree` を実行する
- **THEN** Issue body の依存キーワードに基づきトポロジカルソートされた phases が `.autopilot/plan.yaml` に出力される

#### Scenario: deps.yaml 競合検出と Phase 分離
- **WHEN** --issues モードで同一 Phase 内に deps.yaml 変更 Issue が2件以上含まれる
- **THEN** deps.yaml 変更 Issue が自動的に sequential Phase に分離される

### Requirement: autopilot-should-skip スクリプト移植

autopilot-should-skip.sh を新リポジトリに移植し、マーカーファイル参照を state-read.sh 経由に置換しなければならない（MUST）。

#### Scenario: 依存先が failed の場合スキップ
- **WHEN** plan.yaml で Issue A が Issue B に依存しており、Issue B の status が `failed` である
- **THEN** exit code 0（skip）を返す

#### Scenario: 依存先が全て done の場合実行
- **WHEN** plan.yaml で Issue A が Issue B に依存しており、Issue B の status が `done` である
- **THEN** exit code 1（実行）を返す

#### Scenario: 依存なしの場合実行
- **WHEN** plan.yaml で Issue A に依存先がない
- **THEN** exit code 1（実行）を返す
