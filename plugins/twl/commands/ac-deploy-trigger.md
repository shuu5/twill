# AC 駆動 deploy E2E トリガー

AC 抽出結果から外部アクセス条件キーワードを検出し、deploy E2E 実行フラグファイルを作成する。

## 入力

- `${SNAPSHOT_DIR}`: セッションスナップショットディレクトリ
- `${SNAPSHOT_DIR}/01.5-ac-checklist.md`: AC 抽出結果（ac-extract の出力）

## 出力

- `${SNAPSHOT_DIR}/01.6-deploy-e2e-flag`

## 冪等性

`${SNAPSHOT_DIR}/01.6-deploy-e2e-flag` が存在する場合、スキップ。

## 実行ロジック（MUST）

```bash
# SNAPSHOT_DIR 検証
if [ -z "${SNAPSHOT_DIR}" ]; then
    echo "ERROR: SNAPSHOT_DIR is not set" >&2
    exit 1
fi

# 冪等性チェック
if [ -f "${SNAPSHOT_DIR}/01.6-deploy-e2e-flag" ]; then
    echo "01.6-deploy-e2e-flag already exists — skipping"
    exit 0
fi

AC_FILE="${SNAPSHOT_DIR}/01.5-ac-checklist.md"

# AC ファイルが存在しない or スキップされた場合
if [ ! -f "${AC_FILE}" ] || grep -qE "^(Issue 番号なし|AC セクションなし) — スキップ$" "${AC_FILE}"; then
    echo "DEPLOY_E2E_REQUIRED=false" > "${SNAPSHOT_DIR}/01.6-deploy-e2e-flag"
    exit 0
fi

# キーワード検出（大文字小文字不問）
KEYWORDS="外部IP|外部アクセス|Tailscale|リモートアクセス|CORS|PNA|Private Network Access|deploy E2E|ネットワーク層"

if grep -qiE "${KEYWORDS}" "${AC_FILE}"; then
    echo "DEPLOY_E2E_REQUIRED=true" > "${SNAPSHOT_DIR}/01.6-deploy-e2e-flag"
    echo "AC に外部アクセスキーワードを検出 — deploy E2E をトリガー"
else
    echo "DEPLOY_E2E_REQUIRED=false" > "${SNAPSHOT_DIR}/01.6-deploy-e2e-flag"
fi
```
