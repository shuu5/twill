# Security gate (Layer A-D) — bypass 禁止・permission 拒否対応

Claude Code permission classifier（Layer A-D 各ゲート）が設けた境界を observer は尊重しなければならない（SHALL）。gate deny を受けた後に別の手段で迂回を試みることは、以降の deny 確率を急上昇させるため厳禁（`refs/pitfalls-catalog.md §12` 参照）。

## Layer A-D ゲート定義

| Layer | 名称 | 目的 |
|-------|------|------|
| A | session-state | autopilot state ファイルへの不正書き換えを防止 |
| B | worker-bash | ホスト環境破壊コマンドの実行を防止 |
| C | git | 不正な git 操作（直接マージ等）を防止 |
| D | refined-label | `refined` ラベルの直接付与を防止（workflow 経由のみ許可） |
| D | refined-status | Status=In Progress への直接遷移を防止（Status=Refined 経由のみ許可、ADR-024） |

## 禁止 bypass 手法（MUST NOT）

- **session file pre-seed**: state ファイルを直接読み書きして gate 判定をスキップする
- **Worker inject with bypass hint**: inject メッセージに「gate を無視して」等のヒントを含める
- **settings self-modification**: `.claude/settings.json` を書き換えて permission ルールを緩和する
- **bypass permission mode の自動提案**: observer が auto → bypass モード切替を自律的に提案・実行する（ユーザー判断領域の越権）

## permission 拒否への正しい対応（MUST）

```
gate deny (1 回目) → STOP（即時停止） → AskUserQuestion でユーザーに状況報告
```

**2 回以上連続で deny が発生した場合**: 即時 STOP し、Layer 2 Escalate（`plugins/twl/refs/intervention-catalog.md` パターン 13）に従って AskUserQuestion でユーザー確認を取ること（MUST）。bypass permission mode の使用可否はユーザーのみが判断できる。observer が auto → bypass 切替を提案してはならない（MUST NOT）。

**参照**: `refs/pitfalls-catalog.md §12`（Claude Code classifier bypass 検出パターン）、`plugins/twl/refs/intervention-catalog.md パターン 13`（2 回 STOP ルール — W5-2 連携）
