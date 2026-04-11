---
type: reference
spawnable_by: [controller, atomic, workflow]
disable-model-invocation: true
---

# Test Scenario Catalog

co-self-improve framework のテストプロジェクト (test-target/main worktree) で実行する負荷シナリオ定義。

## scenario YAML フォーマット

各シナリオは以下のスキーマで定義:

```yaml
<scenario-id>:
  level: smoke | regression | load
  description: <一行説明>
  issues_count: <数>
  expected_duration_min: <最小分>
  expected_duration_max: <最大分>
  expected_conflicts: <件数>
  expected_pr_count: <件数>
  observer_polling_interval: <秒>
  issue_templates:
    - title: <タイトル>
      body: <body, multi-line>
      labels: [...]
      complexity: trivial | medium | complex
```

## smoke level シナリオ (1 Issue, trivial change)

### smoke-001: hello world function

```yaml
smoke-001:
  level: smoke
  description: "単一 Issue, hello world 関数追加, trivial"
  issues_count: 1
  expected_duration_min: 2
  expected_duration_max: 5
  expected_conflicts: 0
  expected_pr_count: 1
  observer_polling_interval: 30
  issue_templates:
    - title: "[Test] add hello() function to test-target plugin"
      body: |
        ## Goal
        test-target plugin に `hello()` 関数を追加する。

        ## AC
        - [ ] `scripts/hello.sh` が新規作成され `echo "hello"` を実行する
        - [ ] chmod +x が設定されている
      labels: [test, scope/test-target, complexity-trivial]
      complexity: trivial
```

### smoke-002: documentation update

```yaml
smoke-002:
  level: smoke
  description: "単一 Issue, README 1行追加, trivial"
  issues_count: 1
  expected_duration_min: 2
  expected_duration_max: 5
  expected_conflicts: 0
  expected_pr_count: 1
  observer_polling_interval: 30
  issue_templates:
    - title: "[Test] update README with project description"
      body: |
        ## Goal
        test-target plugin の README.md に概要説明を 1 行追加する。

        ## AC
        - [ ] README.md の先頭に `# test-target` ヘッダがある
        - [ ] 概要説明が 1 行以上追加されている
      labels: [test, scope/test-target, complexity-trivial]
      complexity: trivial
```

## regression level シナリオ (3-5 Issue 並列, 想定 conflict 1-2)

### regression-001: parallel atomic implementation

```yaml
regression-001:
  level: regression
  description: "3 Issue 並列, 同じ deps.yaml を編集, conflict 1 件想定"
  issues_count: 3
  expected_duration_min: 10
  expected_duration_max: 30
  expected_conflicts: 1
  expected_pr_count: 3
  observer_polling_interval: 15
  issue_templates:
    - title: "[Test] add atomic A"
      body: |
        ## Goal
        atomic A コマンドを追加する。

        ## AC
        - [ ] commands/atomic-a.md が新規作成されている
        - [ ] deps.yaml に atomic-a エントリが追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
    - title: "[Test] add atomic B"
      body: |
        ## Goal
        atomic B コマンドを追加する。

        ## AC
        - [ ] commands/atomic-b.md が新規作成されている
        - [ ] deps.yaml に atomic-b エントリが追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
    - title: "[Test] add atomic C"
      body: |
        ## Goal
        atomic C コマンドを追加する。

        ## AC
        - [ ] commands/atomic-c.md が新規作成されている
        - [ ] deps.yaml に atomic-c エントリが追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
```

### regression-002: 5 issue parallel with shared file

```yaml
regression-002:
  level: regression
  description: "5 Issue 並列, README + deps.yaml + scripts/ を並列編集, conflict 2 件想定"
  issues_count: 5
  expected_duration_min: 15
  expected_duration_max: 30
  expected_conflicts: 2
  expected_pr_count: 5
  observer_polling_interval: 15
  issue_templates:
    - title: "[Test] add utility script alpha"
      body: |
        ## Goal
        scripts/alpha.sh を追加し README に説明を追記する。

        ## AC
        - [ ] scripts/alpha.sh が新規作成されている
        - [ ] README.md に alpha の説明行が追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
    - title: "[Test] add utility script beta"
      body: |
        ## Goal
        scripts/beta.sh を追加し README に説明を追記する。

        ## AC
        - [ ] scripts/beta.sh が新規作成されている
        - [ ] README.md に beta の説明行が追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
    - title: "[Test] add utility script gamma"
      body: |
        ## Goal
        scripts/gamma.sh を追加し deps.yaml に登録する。

        ## AC
        - [ ] scripts/gamma.sh が新規作成されている
        - [ ] deps.yaml に gamma エントリが追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
    - title: "[Test] add utility script delta"
      body: |
        ## Goal
        scripts/delta.sh を追加し deps.yaml に登録する。

        ## AC
        - [ ] scripts/delta.sh が新規作成されている
        - [ ] deps.yaml に delta エントリが追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
    - title: "[Test] add utility script epsilon"
      body: |
        ## Goal
        scripts/epsilon.sh を追加し README と deps.yaml 両方を更新する。

        ## AC
        - [ ] scripts/epsilon.sh が新規作成されている
        - [ ] README.md に epsilon の説明行が追加されている
        - [ ] deps.yaml に epsilon エントリが追加されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
```

### regression-003: full-chain regression

```yaml
regression-003:
  level: regression
  description: "DeltaSpec + medium complexity Issue で setup→test-ready→pr-verify→pr-merge の full-chain 遷移を検証"
  issues_count: 1
  expected_duration_min: 15
  expected_duration_max: 35
  expected_conflicts: 0
  expected_pr_count: 1
  observer_polling_interval: 15
  issue_templates:
    - title: "[Test] add greet() function with DeltaSpec"
      body: |
        ## Goal
        test-target plugin に `greet(name)` 関数を追加する。DeltaSpec を使用して実装すること。

        ## AC
        - [ ] `scripts/greet.sh` が新規作成され `echo "Hello, $1"` を実行する
        - [ ] `deltaspec/changes/` に DeltaSpec change が存在する
        - [ ] chmod +x が設定されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
```

### regression-004: Bug #436 再現（issue: フィールド欠落）

```yaml
regression-004:
  level: regression
  description: "twl spec new が .deltaspec.yaml に issue: フィールドを生成しない Bug #436 の再現シナリオ"
  issues_count: 1
  expected_duration_min: 10
  expected_duration_max: 20
  expected_conflicts: 0
  expected_pr_count: 1
  observer_polling_interval: 15
  issue_templates:
    - title: "[Test] add farewell() function with DeltaSpec (Bug436 repro)"
      body: |
        ## Goal
        test-target plugin に `farewell(name)` 関数を追加する。DeltaSpec を使用して実装すること。

        ## Bug 再現条件
        この Issue は Bug #436 の再現用シナリオ。autopilot が `twl spec new` を呼び出した後、
        生成される `.deltaspec.yaml` に `issue:` フィールドが存在するかを検証する。
        `issue:` フィールドが欠落した場合、orchestrator の `grep "^issue:"` が 0 件ヒットし
        archive フェーズで失敗する。

        ## AC
        - [ ] `scripts/farewell.sh` が新規作成され `echo "Goodbye, $1"` を実行する
        - [ ] `deltaspec/changes/*.yaml` に `issue:` フィールドが存在する（Bug #436 修正検証）
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
```

### regression-005: Bug #438 再現（Orchestrator polling timeout）

```yaml
regression-005:
  level: regression
  description: "Orchestrator polling loop が Bash timeout 120秒で停止し inject_next_workflow() が呼ばれない Bug #438 の再現シナリオ"
  issues_count: 1
  expected_duration_min: 15
  expected_duration_max: 30
  expected_conflicts: 0
  expected_pr_count: 1
  observer_polling_interval: 10
  issue_templates:
    - title: "[Test] add slow-init script with heavy setup (Bug438 repro)"
      body: |
        ## Goal
        test-target plugin に `scripts/slow-init.sh` を追加する。このスクリプトは初期化に
        時間がかかる処理を含む（複数ファイルの生成とループ処理）。

        ## Bug 再現条件
        この Issue は Bug #438 の再現用シナリオ。workflow-setup フェーズで change-propose が
        120 秒以上かかる処理を含む場合、Orchestrator の polling loop が Bash timeout で停止し、
        `inject_next_workflow()` が呼ばれず chain 遷移が停止することを検証する。

        ## AC
        - [ ] `scripts/slow-init.sh` が新規作成されている
        - [ ] スクリプト内に 10 個以上のファイルを生成するループが含まれている
        - [ ] chmod +x が設定されている
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
```

### regression-006: Bug #439 再現（merge-gate phase-review チェック欠落）

```yaml
regression-006:
  level: regression
  description: "merge-gate が phase-review.json の存在を検査しない Bug #439 の再現シナリオ"
  issues_count: 1
  expected_duration_min: 10
  expected_duration_max: 25
  expected_conflicts: 0
  expected_pr_count: 1
  observer_polling_interval: 15
  issue_templates:
    - title: "[Test] add config.yaml with minimal changes (Bug439 repro)"
      body: |
        ## Goal
        test-target plugin に `config.yaml` を追加し、プラグイン設定の基本構造を定義する。

        ## Bug 再現条件
        この Issue は Bug #439 の再現用シナリオ。workflow-pr-verify の review フェーズが
        実行されないまま merge-gate に到達した場合、`phase-review.json` が不在でも
        merge-gate が PASS してしまうことを検証する。trivial な変更で pr-verify の
        reviewer specialist が起動されない条件を意図的に作る。

        ## AC
        - [ ] `config.yaml` が新規作成され `name: test-target` が含まれている
        - [ ] merge-gate 到達時に `.autopilot/checkpoints/phase-review.json` の存在が
              確認される（Bug #439 修正検証）
      labels: [test, scope/test-target, complexity-medium]
      complexity: medium
```

## load level シナリオ (8-12 Issue, conflict 5+)

**注意**: 本 reference では **smoke + regression のみ定義**。load level は将来別 Issue で追加する。

```yaml
# load-001: TBD (将来 Issue で実装)
# load-002: TBD (将来 Issue で実装)
```
