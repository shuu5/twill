## Context

su-compact コマンド（Step 3）が Working Memory 退避処理を自ら行っているが、外部化ロジックが肥大化している。externalize-state を atomic コマンドとして切り出すことで責務を明確化し、再利用可能にする。

externalization-schema.md が `refs/` に既に存在（#363 完了済み）しており、書き出し先パスとフロントマター構造が定義済み。

## Goals / Non-Goals

**Goals:**
- SupervisorSession の現在状態を externalization-schema に従って外部ファイルへ書き出す atomic コマンドを作成する
- `trigger` 引数で書き出しモードを制御する（`auto_precompact` / `manual` / `wave_complete`）
- ExternalizationRecord を `.autopilot/session.json` に追記する
- su-compact から呼び出せる形式にする

**Non-Goals:**
- Memory MCP への保存（su-compact が担当）
- compaction 実行（su-compact が担当）
- PostCompact 復元処理（su-observer が担当）

## Decisions

**書き出し先の決定**: `trigger=wave_complete` の場合のみ `wave-{N}-summary.md` を使用。それ以外は `working-memory.md`。Wave 番号は `.autopilot/session.json` から読む。

**ExternalizationRecord フォーマット**: session.json の `externalization_log` 配列に以下を追記:
```json
{
  "externalized_at": "<ISO8601>",
  "trigger": "<trigger値>",
  "output_path": "<実際の書き出しパス>"
}
```

**atomic 設計**: externalize-state 単体で完結する。su-compact から任意に呼び出せる（存在しない場合はエラーなしでスキップ）。

**引数インターフェース**:
- `--trigger <mode>`: `auto_precompact` / `manual` / `wave_complete`（デフォルト: `manual`）

## Risks / Trade-offs

- **Wave 番号の取得**: session.json に `current_wave` フィールドがない場合、wave-summary のファイル名が不定になる。→ 存在しない場合は `wave-unknown-summary.md` にフォールバック
- **deps.yaml 追加**: `externalize-state` を atomic コマンドとして登録。参照元は `su-compact`（`calls` 依存）
