## Context

auto-merge.md は現在 LLM が bash コードブロックを解釈実行する形式。merge-gate-execute.sh には既に CWD ガード（Layer 2）と tmux window ガード（Layer 3）が実装されており、同等のパターンを auto-merge.sh に適用する。state-read.sh / state-write.sh は既存のインターフェースをそのまま利用する。

## Goals / Non-Goals

**Goals:**

- auto-merge ロジックを bash script に移行し、LLM 解釈実行を排除
- 4 Layer ガードで不変条件 C（Worker マージ禁止）を機械的に担保
- merge-gate-execute.sh と同等のセキュリティガード（CWD, tmux window）を適用
- 非 autopilot 時の従来動作（squash merge + worktree 削除）を維持

**Non-Goals:**

- Pilot 側 command.md の script 化（別 Issue）
- AUTOPILOT_DIR 伝搬バグの根本修正（auto-merge.sh 内フォールバックで対処）
- merge-gate-execute.sh のリファクタリング
- #119 の他ステップの script 化

## Decisions

1. **Layer 順序**: Layer 2（CWD）→ Layer 3（tmux）→ Layer 1（state-read.sh）→ Layer 4（フォールバック）の順で実行。安価なガードを先に配置し、早期 exit で不要な I/O を回避
2. **merge-gate-execute.sh との重複**: auto-merge.sh は独立 script として実装。merge-gate-execute.sh は Pilot が呼ぶもの、auto-merge.sh は Worker/手動が呼ぶもの。役割が異なるため統合しない
3. **引数方式**: `--issue`, `--pr`, `--branch` の名前付き引数。環境変数ではなく明示的な引数で渡し、呼び出し側の意図を明確にする
4. **OpenSpec archive**: 非 autopilot 時のみ実行。既存の auto-merge.md の archive ロジックを移植
5. **worktree 削除**: 非 autopilot 時のみ実行。merge-gate-execute.sh と同等のロジック（worktree remove → remote branch delete）

## Risks / Trade-offs

- **merge-gate-execute.sh との重複コード**: CWD ガード・tmux ガードは両 script に存在する。共通化は将来の検討事項とし、現時点では独立性を優先
- **AUTOPILOT_DIR 未設定時のフォールバック**: git worktree list → main worktree 特定 → .autopilot/ 直接確認。main worktree が見つからない場合はフォールバックをスキップし、IS_AUTOPILOT=false として扱う（安全側に倒さない設計だが、Layer 1-3 で十分にカバー）
