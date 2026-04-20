## A. specialist-audit.sh 新規作成

- [x] A.1 `plugins/twl/scripts/specialist-audit.sh` を新規作成（--issue/--jsonl/--mode/--manifest-file/--quick/--warn-only/--json/--summary オプション、exit 0/1 の 2 値）
- [x] A.2 JSONL パス解決ロジック（グロブ前方一致 + Issue 番号マッチ + フォールバック）を実装
- [x] A.3 期待集合生成（pr-review-manifest.sh 呼び出し、--manifest-file 再利用オプション）を実装
- [x] A.4 実行集合抽出（JSONL から twl:twl:worker-* を grep）を実装
- [x] A.5 突合ロジック（expected ⊆ actual、missing/extra 計算）と JSON 出力を実装
- [x] A.6 SPECIALIST_AUDIT_MODE=warn|strict、SKIP_SPECIALIST_AUDIT=1 の環境変数対応を実装
- [x] A.7 audit ログ保存（.audit/<run_id>/specialist-audit-<issue>-<ts>-<pid>.json）を実装

## B. merge-gate-check-spawn.sh 拡張

- [x] B.1 `merge-gate-check-spawn.sh` の末尾（MANIFEST_FILE ブロック外）に specialist-audit.sh 呼び出しを追加

## C. su-observer SKILL.md 更新

- [x] C.1 `su-observer/SKILL.md` の L369 `twl audit snapshot` 直後に specialist-audit.sh 一括呼び出しを追加（for issue_json ループ、--warn-only、.audit/wave-N/specialist-audit.log に追記）
