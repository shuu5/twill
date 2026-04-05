# テストフェーズ

サービスヘルスチェック、E2E 品質ゲート、テスト実行を統合する composite フェーズ。
chain 外のスタンドアロンコマンドとして配置（手動テスト実行やデバッグ用途で独立利用可能）。

## 実行フロー

### Step 0: サービスヘルスチェック（services.yaml 存在時）

テスト実行前に `services.yaml` を確認し、required サービスの起動状態をチェック:

- **services.yaml なし**: スキップして Step 1 へ
- **全 required 起動済み**: PASS → Step 1 へ
- **未起動サービスあり**: `/twl:services up` を自動実行 → ヘルスチェック待機 → Step 1 へ
- **タイムアウト**: テストフェーズ失敗として返す

### Step 1: E2E 品質ゲート（E2E テスト含む場合）

```
Task(subagent_type="dev:e2e-quality", prompt="E2E品質ゲート判定: ...")
```

品質ゲート判定:
- **PASS**: テスト実行へ
- **WARN**: 警告表示してテスト実行へ
- **FAIL**: テスト修正を提案

### Step 1.5: deploy E2E フラグ確認

SNAPSHOT_DIR から `01.6-deploy-e2e-flag` を読み取り、deploy E2E の必要性を判定:

- `DEPLOY_E2E_REQUIRED=true`: deploy E2E を追加実行
- `DEPLOY_E2E_REQUIRED=false` またはファイルなし: 従来どおり

### Step 2: テスト実行

```
Task(subagent_type="dev:pr-test", prompt="テスト実行: --type {unit|e2e|all}. deploy E2E: ${DEPLOY_E2E_REQUIRED}")
```

プロジェクト種類の自動検出:
- package.json → `npm test`
- pyproject.toml → `pytest`
- DESCRIPTION (R) → `Rscript -e "testthat::test_local()"`

### Step 3: 結果判定

- **成功**: 次フェーズへ
- **失敗**: fix-phase へ

## 実行ロジック（MUST）

### specialist 呼び出し（MUST）

specialist は **Task tool** で呼び出す。Skill tool は使用不可。

### 禁止事項（MUST NOT）

- Skill tool で specialist 呼び出し禁止
- このコマンド内で修正を行わない（テスト結果の報告のみ）
