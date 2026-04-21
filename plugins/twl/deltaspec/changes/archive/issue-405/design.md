## Context

ADR-021 で Orchestrator が mergegate.py 経由でマージを実行する設計が定義されているが、autopilot.md の不変条件にはこの責務分担が明記されていない。また autopilot-orchestrator.sh の fallback パス（line 868 付近）に「auto-merge.sh にフォールバック」というコメントがあるが、実際のコードは `return 1` するだけで auto-merge.sh を呼び出していない。

## Goals / Non-Goals

**Goals:**
- autopilot.md の Constraints セクションに不変条件 L を追加し、マージ実行責務を明文化する
- autopilot-orchestrator.sh の fallback パスのコメントを実態に合わせて修正する

**Non-Goals:**
- auto-merge.sh、mergegate.py、chain-runner.sh のコード変更
- 既存のマージフロー動作変更
- Observer の intervene-auto.md の変更

## Decisions

1. **不変条件 L の文言**: 「autopilot 時のマージ実行は Orchestrator の mergegate.py 経由のみ。Worker chain の auto-merge ステップは merge-ready 宣言のみを行い、マージは実行しない」
   - 既存の不変条件（K: Pilot 実装禁止等）のパターンに倣い簡潔に記述する

2. **コメント修正箇所**: autopilot-orchestrator.sh の fallback パスのコメントを「実際は return 1 のみ（auto-merge.sh は呼び出さない）」の旨に修正する

## Risks / Trade-offs

- リスクなし（ドキュメント・コメントのみの変更）
- autopilot.md に不変条件を追加することで将来の設計変更時に制約として機能する（意図的）
