## Architecture

### specialist-audit.sh の設計

```
specialist-audit.sh
  ├── JSONL パス解決（--issue N → グロブ前方一致 → Issue 番号マッチ）
  ├── 実行集合抽出（grep "subagent_type":"twl:twl:worker-*"）
  ├── 期待集合生成（pr-review-manifest.sh --mode merge-gate）
  ├── 突合（expected ⊆ actual 検証）
  ├── 出力（JSON stdout）
  └── audit ログ保存（.audit/<run_id>/specialist-audit-<issue>-<ts>-<pid>.json）
```

### JSONL パス解決の注意点

1. **99 文字切り捨て**: Claude Code はプロジェクトディレクトリ名を 99 文字で切り捨てる → グロブ前方一致検索が必須
2. **sequential JSONL 競合**: 複数 Issue を同一 worktree で処理すると複数 JSONL が蓄積 → Issue 番号マッチで絞り込み、フォールバックは最新 JSONL

### bootstrapping 戦略

| Stage | SPECIALIST_AUDIT_MODE | 動作 |
|-------|----------------------|------|
| 0-1 (初回 PR) | warn | 全 FAIL を WARN に降格、exit 0 |
| 2 (本番) | strict | FAIL → exit 1、merge REJECT |

### merge-gate-check-spawn.sh 統合

```
[既存] MANIFEST_FILE ブロック（LLM 自己申告検証）
[新規] specialist-audit.sh 呼び出し（JSONL 独立検証、MANIFEST_FILE ブロック外）
```

`set -euo pipefail` 環境での exit code 捕捉: `|| audit_exit=$?` で明示的に取得。

### su-observer 統合

Wave 完了時に全 Issue の JSONL を一括監査:
- `--warn-only` フラグで merge-gate の strict モードを経由せず監査
- `.audit/wave-${WAVE_NUM}/specialist-audit.log` に追記
- FAIL 行は次 Wave の観察対象（自動起票は行わない）
