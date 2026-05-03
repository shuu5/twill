# ADR-0011: shadow log パス許可リスト設計

## ステータス

Accepted

## コンテキスト

`mcp-shadow-merge-guard-writer.sh` は `SHADOW_LOG_PATH` 環境変数または `--log` 引数で指定されたパスに JSONL 形式でログを書き込む。
このパスが検証されない場合、以下のリスクが生じる:

- **symlink attack**: 攻撃者が `/tmp/mcp-shadow.log` を `/etc/cron.d/evil` へのシンボリックリンクに差し替え、hook 経由でシステムファイルを上書き
- **任意パス書き込み**: CI 環境やコンテナで hook が root 権限で動作する場合、任意のシステムファイルへの書き込みが可能

## 決定

`LOG_FILE` の書き込み前に許可プレフィックス先頭一致チェックを行う。

### 許可リスト

| プレフィックス | 理由 |
|---|---|
| `/tmp/` | OS が保証する一時ファイル領域。UID スコープのサブディレクトリと組み合わせることで隔離を確保 |
| `${HOME}/.cache/` | ユーザー専用キャッシュ領域。他ユーザーからの書き換えが困難 |
| `${SUPERVISOR_DIR}/` | su-observer が管理する専用ディレクトリ（設定時のみ）。Observer ワークスペースへの集約ログに対応 |

### fail-open の選択

不正パス検出時は **hook 全体を失敗させない**（fail-open）。
shadow log は diagnostics 用途であり、書き込み失敗が merge-guard 本体の判断を妨げるべきではない。

```
不正パス検出 → stderr に WARNING 出力 → exit 0（hook を通す、shadow log のみ skip）
```

## 結果

- 任意パス書き込みリスクを排除（最小権限原則の適用）
- hook の可用性を維持（fail-open）
- regression テスト: `plugins/twl/tests/bats/hooks/mcp-shadow-merge-guard-writer-path-validation.bats`

## 参照

- Issue #1280: symlink attack 対策の初期実装（UID スコープ /tmp パス）
- Issue #1336: 許可リスト先頭一致チェックの追加
