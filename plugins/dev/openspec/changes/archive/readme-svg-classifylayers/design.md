## Context

README.md は現在 SVG グラフの埋め込みのみで構成されている（65行）。loom#48 で classify_layers が v3.0 対応され、`loom update-readme` で全コンポーネントが SVG に反映されるようになった。この修正を前提に SVG 再生成と人間向けコンテンツの追加を行う。

現在のコンポーネント構成:
- skills: 9（controller 4 + workflow 5）
- commands: 87（atomic 78 + composite 9）
- agents: 26（specialist 26）
- refs: 15（reference 15）
- scripts: 27

## Goals / Non-Goals

**Goals:**

- `loom update-readme` で SVG を再生成し、全コンポーネントを反映
- README.md にプラグイン概要・設計哲学を記載
- エントリーポイント表（4 controllers + 5 workflows）を追加
- コンポーネント数サマリーテーブルを追加
- 基本的な使い方セクションを追加

**Non-Goals:**

- deps.yaml の構造変更
- loom CLI 自体の修正（loom#48 は別リポジトリで対応済み）
- 各コンポーネントの詳細ドキュメント作成

## Decisions

1. **README 構造**: SVG グラフセクションの前にテキストコンテンツを配置。概要 → エントリーポイント → コンポーネント数 → 使い方 → Architecture（SVG）の順
2. **エントリーポイント表**: deps.yaml の `entry_points` と `chains` から自動的に情報を取得せず、手動で記述（変更頻度が低いため）
3. **コンポーネント数**: deps.yaml から実際の値を取得して記載。将来の自動更新は別 Issue で対応
4. **SVG 再生成**: `loom update-readme` を実行するのみ。loom#48 の修正が前提

## Risks / Trade-offs

- **リスク**: loom#48 が未マージの場合、SVG が不完全なまま生成される。ただし Issue の前提条件として明記済み
- **トレードオフ**: コンポーネント数を手動記載するため、将来のコンポーネント追加時に README が古くなる可能性がある。自動化は別途検討
