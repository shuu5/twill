## Context

Phase 6（su-observer 導入）で旧 Observer コンポーネントが Supervisor に改名された。`intervention-catalog.md` は介入判断ルールを定義する reference ファイルであり、`intervene-*.md` はその判断を実行するコマンドである。これらファイルに旧称 "Observer" が残存しており、supervisor-redesign の命名統一が不完全な状態にある。

変更は単純な文字列置換だが、置換対象の判断が必要：
- **置換対象**: 介入判断・実行主体としての "Observer"（メタ認知コンテキスト）
- **置換対象外**: Live Observation コンテキストの Observer（観察行為そのものを指す用語）

## Goals / Non-Goals

**Goals:**
- intervention-catalog.md と intervene-*.md の "Observer" をメタ認知文脈で "Supervisor" に統一
- `twl check` PASS を維持

**Non-Goals:**
- spawnable_by フィールドの変更（元々 observer は含まれていない）
- 他ファイルの Observer 参照の変更（このスコープ外）
- Live Observation 文脈の "Observer" の変更

## Decisions

1. **sed/grep ではなく手動確認**: 各行の文脈を確認して置換の要否を判断する
2. **`twl check` で事後確認**: 変更後に `twl check` を実行して構造整合性を確認する

## Risks / Trade-offs

- リスク低: 単純な文字列置換であり、機能的な影響はない
- 文脈判断ミスのリスク: "Observer" が Live Observation 文脈か Supervisor 文脈かを誤判断する可能性があるが、変更箇所が少ないため人力確認で対処可能
