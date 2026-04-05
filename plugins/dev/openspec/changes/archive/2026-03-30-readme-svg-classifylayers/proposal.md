## Why

README.md が SVG グラフのみで構成されており、プロジェクトの概要・エントリーポイント・コンポーネント構成が記載されていない。また loom#48（classify_layers v3.0 対応）修正後に SVG を再生成する必要がある。

## What Changes

- `loom update-readme` を実行して SVG グラフを再生成（全87コマンドが表示される状態に）
- README.md にプラグイン概要セクションを追加（設計哲学: chain-driven + autopilot-first）
- README.md にエントリーポイント表を追加（4 controllers + 5 workflows）
- README.md にコンポーネント数テーブルを追加（skills/commands/agents/refs/scripts）
- README.md に基本的な使い方セクションを追加

## Capabilities

### New Capabilities

- README.md にプラグイン概要・設計哲学の記載
- エントリーポイント表（controllers/workflows の一覧と役割）
- コンポーネント数サマリーテーブル
- 基本的な使い方ガイド

### Modified Capabilities

- SVG グラフの再生成（classify_layers v3.0 対応後の全コンポーネント反映）

## Impact

- 影響ファイル: `README.md`, `docs/*.svg`
- API 変更: なし
- 依存関係: loom#48（classify_layers v3.0 対応）が前提
