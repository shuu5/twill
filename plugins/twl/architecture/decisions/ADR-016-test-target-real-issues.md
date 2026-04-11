# ADR-016: test-target --real-issues モード設計

## Status

Proposed

## Date

2026-04-11

## Context

autopilot の full chain（setup → test-ready → pr-verify → pr-merge）は GitHub Issue/PR を前提とした chain 遷移を持つ。現在の co-self-improve は `--local-only` モード（`test-project-scenario-load` による Issue ファイル配置のみ）でシナリオを実行しており、chain 遷移を通せない。

具体的な問題:
- Orchestrator の polling → `inject_next_workflow` → merge-gate の一連のフローはローカルファイルだけでは動作しない
- Bug #436/#438/#439 の再現・回帰防止には実際の GitHub Issue + PR を使った full chain 実行が不可欠

observation.md の不変制約 **"test target は実 twill main の git 履歴を絶対に汚染しない"** が設計の起点となる。

## 3 選択肢比較

| 戦略 | 隔離性 | GitHub API 依存 | クリーンアップ複雑度 | 実装複雑度 |
|------|--------|----------------|---------------------|-----------|
| **専用テストリポ** | 高 | 中（リポ作成 API） | 低 | 低 |
| 実リポ test ラベル付き Issue | 低 | 低 | 高 | 低 |
| mock GitHub API | 高 | なし | なし | 高 |

**専用テストリポ**: 独立した GitHub リポジトリに Issue/PR を作成してテストする。実リポと完全に分離されるため不変制約を自然に満たす。

**実リポ test ラベル付き Issue**: 実リポジトリ（twill）に `test:` ラベルを付けた Issue を作成する。隔離性が低く、PR マージが実リポの main を汚染するリスクがある。観察 observation.md の不変制約に **抵触する可能性が高い**。

**mock GitHub API**: GitHub API をモックし、外部依存なしでテストする。完全な隔離と高速なテストが可能だが、実際の GitHub webhook/event 動作を再現できないため、autopilot の chain 遷移テストの信頼性が低下する。実装コストも高い。

## Decision

**専用テストリポを採用する。**

選定根拠:
1. observation.md の不変制約（実 main 汚染禁止）を完全に満たす唯一の現実的選択肢
2. クリーンアップは PR/Issue/branch をテストリポ内で処理するだけで済み、複雑度が低い
3. 実際の GitHub API を使うため autopilot の chain 遷移テストの信頼性が高い
4. mock GitHub API に比べて実装コストが大幅に低い

## co-self-improve 統合フロー（--real-issues モード）

co-self-improve SKILL.md の Step 1 に `--real-issues` 分岐を追加する:

```
## Step 1: scenario-run モード — シナリオ選択 + spawn

### 既存フロー（--local-only）
1. test-project-init → test-target worktree 作成（なければ）
2. test-scenario-catalog.md を Read → シナリオ選択
3. test-project-scenario-load → Issue ファイルをローカルに配置
4. session:spawn で observed session 起動

### 追加分岐（--real-issues）[ADR-016]
1. test-project-init --mode real-issues → 専用テストリポ作成（既存ならスキップ）
2. test-scenario-catalog.md を Read → シナリオ選択
3. 選択シナリオに対応する GitHub Issue を専用テストリポに起票
   （gh issue create --repo <test-repo> --label "test:scenario"）
4. autopilot start --repo <test-repo> --issue <N>
5. session:spawn で observed session 起動（--cd worktrees/test-target）
6. spawn 後の window 名を取得し Step 2 へ
```

**分岐追加箇所**: `plugins/twl/skills/co-self-improve/SKILL.md` の Step 1 冒頭にモード判定分岐を追加する（将来の実装 Issue で対応）。

## クリーンアップ設計

テスト完了後（成功・失敗問わず）、以下の順序でクリーンアップを実行する:

```
1. feature branch 削除
   - gh api DELETE /repos/{test-repo}/git/refs/heads/{branch}
   - 対象: 専用テストリポの branch のみ

2. PR クローズ（マージ済みは自動クローズ済み）
   - gh pr close <N> --repo <test-repo>
   - 未マージの場合のみ実行

3. Issue クローズ（テスト結果ラベル付与）
   - gh issue close <N> --repo <test-repo>
   - ラベル: test-result:pass または test-result:fail

4. テストリポ自体は保持（次回テストで再利用）
```

### 冪等性設計

クリーンアップは再実行可能（冪等）でなければならない:
- branch 削除: 既に削除済みなら 404 を無視
- PR クローズ: 既にクローズ済みなら noop
- Issue クローズ: 既にクローズ済みなら noop

失敗時のリトライ: 各ステップは独立して再実行可能とし、前ステップの成功を前提としない。

## リポジトリ管理の責務帰属

**`test-project-init` コマンドに `--mode real-issues` フラグを追加する（既存コマンド拡張）。**

選定根拠:
- 新規コマンド作成より既存コマンドの責務を明確に拡張する方が deps.yaml 管理が単純
- `test-project-init` はすでに test-target worktree 管理の責務を持っており、リポジトリ作成はその自然な拡張

**テストリポのライフサイクル管理ルール（増殖防止ポリシー）**:
- テストリポ名: `twill-test-<YYYYMM>` （月次でローテーション）
- 同月の既存リポがあれば再利用（再作成不要）
- リポは `private` で作成する
- 使用していないリポの削除は `test-project-manage` モードから手動実行（自動削除禁止）

## Consequences

**正の影響:**
- Bug #436/#438/#439 のような chain 遷移バグを自動テストで再現・検知できるようになる
- 実リポの git 履歴汚染ゼロが保証される
- クリーンアップが単純で、テスト後の状態が明確

**負の影響・リスク:**
- GitHub Actions の無料枠消費が増える可能性がある（専用リポでの CI 実行）
- 専用テストリポの作成に GitHub API トークンと適切な権限が必要
- 月次リポローテーションにより、前月の Issue/PR 履歴は新リポに引き継がれない

**残留リスク:**
- GitHub API のレートリミットが連続テスト実行に影響する可能性がある
- クリーンアップが不完全な場合、孤立した branch/Issue が残る可能性がある（冪等性設計で緩和）
