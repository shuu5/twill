# ADR-005: Self-Improve Review 設計（ユーザートリガー + 機械的エラー記録）

## Status
Accepted

## Context

旧 dev plugin の self-improve 機能は autopilot 内部の自動パターン検出のみ。
ユーザーが会話中にエラーや仕様と異なる動作を発見した場合、手動で Issue 化する手段がなかった。

一方、完全自動化は困難:
- テスト実行、エラー調査など、エラーが想定される作業がある
- 「エラー = 問題」ではない。問題かどうかの判断は人間が行うべき
- 会話コンテキストの解釈は高コスト

## Decision

### 3層分離アーキテクチャ

1. **機械層 (Hook)**: PostToolUse hook で Bash exit_code != 0 を `.self-improve/errors.jsonl` に記録
   - サイレント、ブロックなし、AI 判断なし
   - 記録は安価（JSONL 追記のみ）

2. **判断層 (User + Command)**: ユーザーが `/twl:self-improve-review` でトリガー
   - エラーサマリーを提示、ユーザーが「問題」と「想定内」を選別
   - 選別された問題の会話コンテキストを参照して構造化

3. **Issue化層 (co-issue)**: `.controller-issue/explore-summary.md` 経由で co-issue フローに接続
   - Phase 1 (explore) をスキップし、Phase 2 (decompose) から続行
   - 既存の co-issue ワークフローを完全再利用

### 新 controller を作らない
- 4 controller 制約（ADR-002）を維持
- self-improve-review は atomic コマンドとして、co-issue の Phase 1 代替入力として機能

## Consequences

### Positive
- エラー記録が機械的で漏れない（hook による自動記録）
- 人間の判断が介在するため、誤検知（テストエラー等）による不要 Issue を防止
- co-issue フローの再利用でコンポーネント増加を最小化
- 「記録するだけ」の原則により、通常作業への影響ゼロ

### Negative
- errors.jsonl がセッションスコープのため、長期的なエラーパターン分析には使えない
- ユーザーがトリガーしないと問題が拾い上げられない（完全自動ではない）

### Risks
- errors.jsonl が大量のエントリを蓄積する可能性（長時間セッション）→ 件数上限またはローテーション検討
