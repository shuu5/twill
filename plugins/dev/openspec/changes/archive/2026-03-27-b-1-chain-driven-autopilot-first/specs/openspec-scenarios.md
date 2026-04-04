## ADDED Requirements

### Requirement: Autopilot Lifecycle シナリオ

autopilot のライフサイクル全体（起動→計画生成→Phase 実行→完了サマリー）を `openspec/specs/autopilot-lifecycle.md` に OpenSpec シナリオとして定義しなければならない（SHALL）。

シナリオは co-autopilot 起動から autopilot-summary までの主要判断分岐をカバーする（MUST）。

#### Scenario: 正常系ライフサイクル
- **WHEN** 単一 Issue（例: #42）で co-autopilot を起動する
- **THEN** plan.yaml 生成 → Phase 1 開始 → Worker 起動 → merge-gate → Phase 完了 → autopilot-summary の順で実行される

#### Scenario: 複数 Phase の逐次実行
- **WHEN** 依存関係のある 3 Issue（#10→#11→#12）で co-autopilot を起動する
- **THEN** plan.yaml に 3 Phase が生成され、Phase 1 完了後に Phase 2 が開始される

#### Scenario: Phase 内 Issue 失敗時の skip 伝播
- **WHEN** Phase 1 の Issue #10 が failed になり、Phase 2 の Issue #11 が #10 に依存している
- **THEN** Issue #11 は自動 skip され、issue-11.json の status が `failed` に遷移する（不変条件 D）

#### Scenario: Emergency Bypass
- **WHEN** co-autopilot 自体の SKILL.md にバグがあり、起動に失敗する
- **THEN** Emergency Bypass で main/ から直接実装→PR→merge が許可され、retrospective 記録が義務付けられる

### Requirement: merge-gate シナリオ

merge-gate ワークフロー（動的レビュアー構築→並列 specialist→結果集約→判定）を `openspec/specs/merge-gate.md` に OpenSpec シナリオとして定義しなければならない（SHALL）。

PASS/REJECT の判定ロジックと retry フローをカバーする（MUST）。

#### Scenario: 動的レビュアー構築
- **WHEN** PR の変更ファイルに deps.yaml と TypeScript ファイルが含まれる
- **THEN** worker-structure, worker-principles, worker-code-reviewer, worker-security-reviewer が specialist リストに追加される

#### Scenario: merge-gate PASS
- **WHEN** 全 specialist の findings に severity=CRITICAL かつ confidence>=80 のエントリがない
- **THEN** merge-gate は PASS を返し、Pilot が squash merge を実行する

#### Scenario: merge-gate REJECT（1回目）
- **WHEN** specialist findings に severity=CRITICAL かつ confidence>=80 のエントリが存在し、retry_count=0
- **THEN** issue-{N}.json の status が failed → running に遷移し、fix_instructions に findings が記録され、Worker が fix-phase を実行する

#### Scenario: merge-gate REJECT（2回目、確定失敗）
- **WHEN** fix-phase 後の再レビューで再度 CRITICAL findings が存在し、retry_count=1
- **THEN** issue-{N}.json の status が failed に確定し、Pilot に手動介入が要求される（不変条件 E）

### Requirement: Project Create シナリオ

co-project によるプロジェクト新規作成（bare repo→worktree→テンプレート→OpenSpec）を `openspec/specs/project-create.md` に OpenSpec シナリオとして定義しなければならない（SHALL）。

bare repo 構造の初期化から Project Board 作成までをカバーする（MUST）。

#### Scenario: 正常系プロジェクト作成
- **WHEN** `co-project create my-project` を実行する
- **THEN** `my-project/.bare/` が作成され、`my-project/main/` worktree が初期化され、テンプレートファイルが配置される

#### Scenario: bare repo 構造検証
- **WHEN** プロジェクト作成完了後にセッションを開始する
- **THEN** `.bare/` 存在、`main/.git` がファイル、CWD が `main/` 配下の 3 条件が全て満たされる

#### Scenario: Project Board 自動作成
- **WHEN** プロジェクト作成時に GitHub リポジトリが指定されている
- **THEN** GitHub Project V2 が自動作成され、リポジトリにリンクされる
