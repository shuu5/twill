## Why

`merge-gate-check-spawn.sh` は LLM 自己申告（SPAWNED_FILE）のみで specialist completeness を判定しており、Worker JSONL による独立検証がない。#722 で specialist review 0 件のまま自動 merge された事故が発生し、observer の手動 JSONL 監査に依存している状況が続いている。

## What Changes

- `plugins/twl/scripts/specialist-audit.sh` を新規作成: Worker JSONL を直読みして specialist completeness を独立検証するスクリプト
- `plugins/twl/scripts/merge-gate-check-spawn.sh` を拡張: JSONL 独立検証ブロックを末尾追加（MANIFEST_FILE ブロック外）
- `plugins/twl/skills/su-observer/SKILL.md` を更新: Wave 完了時に各 Issue の specialist completeness を自動監査

## Capabilities

### New Capabilities

- **JSONL 独立検証**: Worker session JSONL から `twl:twl:worker-*` を抽出し、`pr-review-manifest.sh` が生成する期待集合と突合する
- **bootstrapping 対応**: `SPECIALIST_AUDIT_MODE=warn` で全 FAIL を WARN に降格（initial deploy 時の誤検知を防止）
- **緊急無効化**: `SKIP_SPECIALIST_AUDIT=1` で即座にスキップ可能
- **merge-gate 統合**: `merge-gate-check-spawn.sh` が specialist-audit.sh を呼び出し、JSONL 独立検証を自動実行

### Modified Capabilities

- **merge-gate-check-spawn.sh**: MANIFEST_FILE ブロック外（スクリプト末尾）に specialist-audit.sh 呼び出しを追加
- **su-observer Wave 完了処理**: twl audit snapshot 直後に全 Issue の specialist completeness を一括監査

## Impact

- `plugins/twl/scripts/specialist-audit.sh`: 新規作成（JSONL 直読み監査ツール）
- `plugins/twl/scripts/merge-gate-check-spawn.sh`: 末尾に specialist-audit.sh 呼び出し追加
- `plugins/twl/skills/su-observer/SKILL.md`: L369 直後に specialist-audit 呼び出し追加
