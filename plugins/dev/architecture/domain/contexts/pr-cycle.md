## Name
PR Cycle

## Responsibility
レビュー、テスト、マージ。verify → 並列レビュー → test → fix → report のチェーン

## Key Entities
- PullRequest, ReviewResult, Finding, MergeGateDecision, SpecialistOutput

## Dependencies
- Autopilot (upstream): autopilot から merge-gate として呼び出される
- Issue Management (upstream): AC 抽出、スコープ判定で Issue 情報を参照

## merge-gate 動的レビュアー構築

旧 standard/plugin 2パスを廃止。変更ファイルからレビュアーリストを動的に構築する。

### 構築ルール

| 条件 | 追加される specialist |
|------|----------------------|
| deps.yaml 変更あり | worker-structure（loom audit/check 統合）+ worker-principles |
| コード変更あり | worker-code-reviewer + worker-security-reviewer |
| Tech-stack 該当あり | conditional specialist（Tech-stack 検出ロジックで決定） |

全 specialist は並列 Task spawn。worktree 分離により逐次実行不要。

### Tech-stack 検出ロジック

- 変更ファイルの拡張子・パスから tech-stack を判定し、該当する conditional specialist を追加する
- 判定ロジックは `script` 型コンポーネントとして実装（merge-gate workflow の chain step から呼び出し）
- 具体的なスクリプト名・判定ルールの詳細は実装時に決定（B-5 スコープ）

### Specialist 共通出力スキーマ

```json
{
  "result": "PASS|FAIL",
  "findings": [{
    "severity": "critical|high|medium|low|info",
    "confidence": 80,
    "file": "src/module.ts",
    "line": 42,
    "message": "...",
    "category": "vulnerability|bug|coding-convention|structure|principles"
  }]
}
```

merge-gate は `severity in [critical, high] && confidence >= 80` で機械的フィルタ。

### merge-gate リトライ制限

- merge-gate リジェクト後のリトライは最大1回（不変条件 E）
- 2回目リジェクト = 確定失敗。Pilot に報告し、手動介入を要求
- merge 失敗時に rebase は試みない（停止のみ、不変条件 F）
