## Name
Autopilot

## Responsibility
セッション管理、Phase 実行、計画生成、cross-issue 影響分析、パターン検出

## Key Entities
- SessionState, IssueState, Phase, AutopilotPlan, CrossIssueWarning

## Dependencies
- PR Cycle (downstream): merge-gate を呼び出してマージ判定
- Issue Management (upstream): Issue 情報を取得
- Self-Improve (downstream): パターン検出時に ECC 照合を自動追加

## 不変条件（9件）

旧プラグインの実装分析から導出。autopilot の再現性・安全性・品質を保証する制約。

| ID | 不変条件 | 概要 |
|----|----------|------|
| **A** | 状態の一意性 | issue-{N}.json の `status` は常に `running`, `merge-ready`, `done`, `failed` のいずれか1つ。定義された遷移パスのみ許可 |
| **B** | Worktree 削除 pilot 専任 | Worker は worktree を作成するが削除しない。削除は常に Pilot (main/) が merge 成功後に実行 |
| **C** | Worker マージ禁止 | Worker は `merge-ready` を宣言するのみ。マージ判断・実行は Pilot が merge-gate 経由で行う |
| **D** | 依存先 fail 時の skip 伝播 | Phase N で fail した Issue に依存する Phase N+1 以降の全 Issue は自動 skip |
| **E** | merge-gate リトライ制限 | merge-gate リジェクト後のリトライは最大1回。2回目リジェクト = 確定失敗 |
| **F** | merge 失敗時 rebase 禁止 | squash merge 失敗時は停止のみ。自動 rebase は行わない（LLM 判断を要する操作を機械化しない） |
| **G** | クラッシュ検知保証 | Worker の crash/timeout は必ず検知され、issue-{N}.json の status が `failed` に遷移する |
| **H** | deps.yaml 変更排他性 | 同一 Phase 内で deps.yaml を変更する複数 Issue は separate Phase に分離して sequential 化 |
| **I** | 循環依存拒否 | plan.yaml 生成時に循環依存を検出した場合、計画を拒否してエラー終了 |

### 旧プラグインから除外した不変条件（3件）と理由

- **.fail window クローズ禁止**: 不変条件 G（クラッシュ検知保証）に包含。推奨事項として残す
- **Compaction 耐性**: 統一状態ファイルで構造的に改善。不変条件 A（状態の一意性）に包含
- **後処理順序不変**: chain-driven 設計により実行順序が deps.yaml chains で機械的に保証されるため不要

## Pilot / Worker 役割分担

### Pilot (CWD = main/)
- Issue 選択（Project Board クエリ）
- Worker の起動（tmux new-window）・監視（ポーリング）
- merge-gate 実行（PR レビュー・テスト・判定）
- Worktree 削除（merge 成功後）
- tmux window kill

### Worker (CWD = worktrees/{branch}/)
- Worktree 作成・ブランチ作成
- 実装（chain ステップの逐次実行）
- テスト実行
- `merge-ready` 宣言（issue-{N}.json の status 更新）
- セッション終了（worktree 削除は行わない）

### ライフサイクル概要

```
Pilot (CWD = main/)
  → tmux new-window -c "PROJECT/main" "cld ..."
  → Worker: worktree 作成 → cd → 実装 → merge-ready → セッション終了
  → Pilot: merge-gate → merge → worktree 削除 → window kill
```

## 並行性の制約

- 同一プロジェクトでの複数 autopilot セッションの同時実行は禁止
- session.json は単一ファイルで排他制御不要
- issue-{N}.json は per-issue のため同一セッション内の複数 Issue 並行処理は安全
- Pilot と Worker 間の issue-{N}.json アクセス: **Pilot = read only, Worker = write**

## Emergency Bypass

co-autopilot 障害時のみ手動パスを許可する。

### 許可条件
- co-autopilot 自体の障害（SKILL.md のバグ、セッション管理の故障等）
- co-autopilot の SKILL.md 自体の修正（bootstrap 問題: main/ で直接編集→commit→push）

### 禁止事項
- trivial change（タイポ等）であっても原則 co-autopilot 経由
- bypass の拡大解釈は禁止

### 義務
- Emergency bypass 使用時は、セッション後に retrospective で理由を記録する
