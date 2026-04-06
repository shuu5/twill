## 1. Reference 移植

- [x] 1.1 loom sync 対象 4 references を refs/ に移植（ref-types, ref-practices, ref-deps-format, ref-architecture）+ 同期マーカー付与
- [x] 1.2 プラグイン固有 4 references を refs/ に移植（ref-architecture-spec, ref-project-model, ref-dci, self-improve-format）
- [x] 1.3 baseline 3 references をフラット配置で refs/ に移植（baseline-coding-style, baseline-security-checklist, baseline-input-validation）
- [x] 1.4 deps.yaml refs セクションに 11 エントリ追加

## 2. Specialist 移植: 構造チェック系（haiku）

- [x] 2.1 worker-structure, worker-principles を移植（model: haiku）
- [x] 2.2 worker-env-validator, worker-rls-reviewer, worker-supabase-migration-checker を移植（model: haiku）
- [x] 2.3 worker-data-validator, template-validator, context-checker を移植（model: haiku）
- [x] 2.4 worker-e2e-reviewer, worker-spec-reviewer を移植（model: haiku）

## 3. Specialist 移植: 品質判断系（sonnet）

- [x] 3.1 worker-code-reviewer, worker-security-reviewer を移植（model: sonnet）
- [x] 3.2 worker-nextjs-reviewer, worker-fastapi-reviewer, worker-hono-reviewer を移植（model: sonnet）
- [x] 3.3 worker-r-reviewer, worker-architecture を移植（model: sonnet）
- [x] 3.4 worker-llm-output-reviewer, worker-llm-eval-runner を移植（model: sonnet）

## 4. Specialist 移植: ユーティリティ系（sonnet）

- [x] 4.1 docs-researcher, pr-test を移植（model: sonnet）
- [x] 4.2 e2e-quality, e2e-generate, e2e-heal, e2e-visual-heal を移植（model: sonnet）
- [x] 4.3 autofix-loop, spec-scaffold-tests を移植（model: sonnet）

## 5. deps.yaml 登録 + 検証

- [x] 5.1 deps.yaml agents セクションに 27 specialist エントリを追加
- [x] 5.2 `loom check` + `loom validate` を実行し全エラー解消
- [x] 5.3 `loom sync-docs --check` を実行し sync 対象 4 ファイルの一致を確認
- [x] 5.4 `loom update-readme` を実行し SVG を再生成
