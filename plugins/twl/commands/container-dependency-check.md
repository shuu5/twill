# コンテナ依存チェック

manifest.yaml の `containers` セクションと `~/container-manager/` の実状態を照合する。

## フロー制御（MUST）

### Step 1: container-manager 存在確認

```bash
ls ~/container-manager/ 2>/dev/null
```

| 状態 | 動作 |
|------|------|
| 存在しない | 「container-manager が見つかりません。コンテナ齟齬チェックをスキップします」と報告して終了 |
| 存在する | Step 2 へ |

### Step 2: manifest.yaml 読み取り

指定された manifest.yaml から `containers.required` と `containers.optional` を読み取る。

### Step 3: コンテナ照合

各コンテナについて `~/container-manager/<name>/` の存在を確認:

```bash
ls ~/container-manager/<container-name>/ 2>/dev/null
```

### Step 4: 結果報告

テーブル形式で結果を出力:

```
## コンテナ依存チェック結果

| コンテナ | 種別 | 状態 | 詳細 |
|---------|------|------|------|
| webapp-dev | required | PASS | ~/container-manager/webapp-dev/ 存在 |
| vllm | optional | WARN | 未検出 — fallback: llm-stub で代替可能 |
```

### Step 5: 不足時の対応

| 種別 | 不足時 |
|------|--------|
| required + fallback あり | WARNING + fallback 内容を表示。続行可 |
| required + fallback なし | ERROR + 「container-manager でセットアップしてください」。ユーザーに続行確認 |
| optional | INFO + fallback 内容を表示（あれば）。自動続行 |

---

## 禁止事項（MUST NOT）

- container-manager のファイルを変更してはならない（読み取り専用）
- コンテナを起動・停止してはならない
