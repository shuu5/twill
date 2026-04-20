---
name: twl:baseline-bash
description: |
  Bash スクリプト品質基準。character class、変数スコープ、set -u 初期化のBAD/GOOD対比。
type: reference
disable-model-invocation: true
---

# Bash Baseline

## 1. Character Class のハイフン配置

bash の character class でハイフン `-` を中間に配置すると範囲指定と誤解され、意図しない文字が欠落するリスクがある。

### BAD: ハイフンが中間（範囲指定と誤解される）

```bash
# BAD: ハイフンが中間 — 範囲指定と誤解されるリスク
[a-z_.-Z0-9]    # .-Z が ASCII 46〜90 の範囲と解釈される可能性
[a-zA-Z0-9/_.-]  # - が . と A の間に入り . から A の ASCII 範囲を指定
```

### GOOD: ハイフンを末尾または先頭に配置

```bash
# GOOD: ハイフンを末尾に配置（ドット `.` はどこでも安全）
[[ "$branch" =~ ^[a-zA-Z0-9/_.−]+$ ]]   # 末尾に配置

# GOOD: ハイフンを末尾に配置（ブランチ名バリデーション）
[[ "$input" =~ ^[a-zA-Z0-9/_.-]+$ ]]    # ハイフンを末尾に配置

# GOOD: バックスラッシュでエスケープ
[[ "$input" =~ ^[a-zA-Z0-9/_.\-]+$ ]]   # バックスラッシュでエスケープ

# GOOD: 先頭に配置
[[ "$input" =~ ^[-a-zA-Z0-9/_.]+$ ]]    # 先頭に配置
```

## 2. for-loop 変数の local 宣言

bash では `for` ループの変数はスコープされないため、呼び出し元の同名変数を破壊するリスクがある。

> **注意**: `local` は bash の関数内でのみ有効。トップレベルスクリプトでは使用できない（`local: can only be used in a function` エラーになる）。

### BAD: local 宣言なし

```bash
# BAD: local 宣言なし — 呼び出し元の同名変数を破壊するリスク
process_items() {
  for item in "${list[@]}"; do
    echo "$item"
  done
}
```

### GOOD: local で宣言してからループ

```bash
# GOOD: local で宣言してからループ（関数内でのみ有効）
process_items() {
  local item
  for item in "${list[@]}"; do
    echo "$item"
  done
}
```

## 3. local 宣言の set -u 初期化

`set -u` 環境で `local var` だけで宣言した変数は未初期化のまま残る。`if` ブロック内でのみ代入される変数が `if` をスキップした場合に `unbound variable` エラーが発生する。

### BAD: set -u 環境で unbound variable エラーになる

```bash
# BAD: set -u 環境で unbound variable エラーになる
process() {
  local result
  if [[ "$condition" == "true" ]]; then
    result="found"
  fi
  echo "$result"  # condition が false なら unbound
}
```

### GOOD: 初期値を指定

```bash
# GOOD: 初期値を指定
process() {
  local result=""
  if [[ "$condition" == "true" ]]; then
    result="found"
  fi
  echo "$result"  # 空文字が出力される（安全）
}
```

## 4. 環境変数パースの IFS 問題

`env | grep` でキー=値を読み込む全ての Bash スクリプトに適用。

### BAD: IFS='=' による分割（値内の = が切り捨てられる）

```bash
# BAD: 値に = を含む場合に切り捨て（DEV_URL=https://host?a=b → val="https://host?a" で b が消失）
while IFS='=' read -r key val; do
    ENV_ARGS+=(--setenv="${key}=${val}")
done < <(env | grep '^DEV_')
```

### GOOD: パラメータ展開で正確にパース

```bash
# GOOD: IFS= で行全体を読み、パラメータ展開で最初の = を基準に分割
while IFS= read -r line; do
    key="${line%%=*}"   # 最初の = より前
    val="${line#*=}"    # 最初の = より後ろ全部
    ENV_ARGS+=(--setenv="${key}=${val}")
done < <(env | grep '^DEV_')
```

## 5. source スクリプトの set -e 制約

`source` で読み込まれるスクリプトに `set -e` / `set -euo pipefail` を付けると、スクリプトが現在のシェル環境で実行されるため、シェルオプションが親シェルに継承される。親シェルが非厳格モード（`set +e`）で動作している場合、`source` 先の `set -e` が親シェル全体を暗黙的に厳格化し、以降のコマンドで意図しない終了を引き起こす。

### BAD: source 想定スクリプトに set -euo pipefail を付ける

```bash
# BAD: source 呼び出し専用スクリプトに set -euo pipefail — 親シェルを暗黙的に厳格化する
set -euo pipefail

setup_env() {
  local tmpdir
  tmpdir=$(mktemp -d)
  git fetch origin
  echo "$tmpdir"
}
```

### GOOD: set -euo pipefail を省略し、個別コマンドにエラーチェックを付ける

```bash
# GOOD: set -euo pipefail を省略し、個別コマンドに明示的なエラーチェックを付ける
# （親シェルのエラーハンドリング設定を汚染しない）

setup_env() {
  local tmpdir
  tmpdir=$(mktemp -d) || return 1
  git fetch origin || return 1
  echo "$tmpdir"
}
```

### GOOD: サブシェルで厳格モードを局所化する

```bash
# GOOD: サブシェル内で set -e を使い、親シェルの設定を汚染しない
run_strict() (
  set -euo pipefail
  git fetch origin
  git merge --ff-only origin/main
)
```

> **補足**: `source` されたスクリプト内では `exit N` ではなく `return N` を使うこと。`exit N` は親シェルごと終了させるため、意図しないセッション終了を引き起こす。
