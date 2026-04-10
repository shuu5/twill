## Context

co-autopilot は Wave（Issue 群の一括実行）を複数 Phase に分けて処理する。Wave 完了後に各 Issue の実行結果を集約するための仕組みが存在しない。session.json に各 Issue の status/pr/retry_count が保存されており、これを読み取って Wave サマリを生成する atomic コマンドを追加する。

出力先の `.supervisor/wave-{N}-summary.md` は su-postcompact.sh（PostCompact hook）でも参照される設計のため、フォーマットの安定性が必要。

## Goals / Non-Goals

**Goals:**
- Wave 番号を受け取り session.json から全 Issue の結果を集約する
- 成功/失敗/介入回数の統計を計算する
- `.supervisor/wave-{N}-summary.md` に構造化 Markdown として出力する
- deps.yaml に type: atomic エントリを追加する

**Non-Goals:**
- su-postcompact.sh の修正（参照設計は Issue 外）
- session.json の構造変更
- リアルタイム監視（Wave 完了後の一括集約のみ）

## Decisions

1. **Wave 番号の導出**: plan.yaml の `session_id` とフェーズ情報から Wave を特定。引数として Wave 番号 N を受け取り、`.autopilot/plan.yaml` の対応 phase から Issue リストを取得する
2. **データソース**: `.autopilot/issues/issue-{N}.json` を各 Issue の状態ソースとする（PR/status/retry_count）
3. **出力形式**: `.supervisor/wave-{N}-summary.md` に Markdown 形式で出力。セクション: 概要統計、Issue 一覧表、介入パターン
4. **エラー処理**: 個別 Issue の状態取得失敗は警告のみでスキップ。全体失敗は非ゼロ終了コード

## Risks / Trade-offs

- plan.yaml の構造が変わると Wave→Phase→Issue マッピングが壊れる（軽微: plan.yaml は安定）
- `.supervisor/` ディレクトリが未作成の場合は `mkdir -p` で作成
