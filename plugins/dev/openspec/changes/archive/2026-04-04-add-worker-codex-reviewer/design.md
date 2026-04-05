## Context

co-issue Phase 3b は現在 issue-critic / issue-feasibility の 2 specialist を並列 spawn するが、どちらも Claude（sonnet）モデルを使う。`scripts/codex-review.sh` が実装済みにもかかわらず dead code 状態。新たに specialist agent として統合し、OpenAI Codex CLI（`codex exec`）の視点を Phase 3b に追加する。

## Goals / Non-Goals

**Goals:**
- `agents/worker-codex-reviewer.md` を specialist agent として実装し、`codex exec --sandbox read-only` で Issue をレビューする
- codex 未インストール / `CODEX_API_KEY` 未設定時に graceful skip（`status: PASS, findings: []`）する
- co-issue Phase 3b で issue-critic / issue-feasibility と並列 spawn され、findings テーブルに統合される
- deps.yaml に登録し `loom check` が PASS する

**Non-Goals:**
- `scripts/codex-review.sh` の修正・削除
- PR cycle phase-review への統合
- Codex 以外の外部 AI レビュアー追加

## Decisions

### 1. agent 自身は sonnet、レビューは codex exec に委譲

agent（sonnet）が環境チェック・入力準備・出力変換を担い、実際のレビューは `codex exec --sandbox read-only` に委譲する。codex の出力は自由形式テキストのため、agent が specialist 共通スキーマ（status + findings[]）に変換する。

### 2. Graceful degradation を Bash チェックで実現

`command -v codex` と `[ -n "$CODEX_API_KEY" ]` で即座に判定し、いずれか失敗時は findings: [] で PASS を返す。エラーメッセージを出力せずサイレントにスキップすることで Phase 3b 全体をブロックしない。

### 3. category は `codex-review` 専用カテゴリを使用

既存の `issue-critique` / `feasibility` と区別できるように専用カテゴリ `codex-review` を使用する。

### 4. deps.yaml への登録パターンは既存 specialist に準拠

`spawnable_by: [workflow, composite, controller]`、`can_spawn: []`、skills に `ref-issue-quality-criteria` と `ref-specialist-output-schema` を列挙する（issue-critic パターンを踏襲）。

## Risks / Trade-offs

- **codex exec のレート制限**: 並列 spawn 時に OpenAI API がレート制限される可能性があるが、graceful degradation で吸収される
- **出力変換の精度**: codex の自由形式テキストを agent が変換するため、findings の抽出精度はプロンプト品質に依存する
- **CI 環境**: `CODEX_API_KEY` が未設定の CI では常に PASS になるが、これは意図した動作
