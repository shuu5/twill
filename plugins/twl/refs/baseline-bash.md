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

## 6. 複数 regex パターンの ^ アンカー一貫性

同一 input source（tmux pane capture 出力など）に対して複数の `grep -E` / `=~` パターンを並走させる場合、各パターンの `^` 直後の character class（leading-space 許容 or strict）を統一しなければならない。形式が混在すると、あるパターンにはマッチするが別のパターンにはマッチしないという誤分類バグが生じる。

**Why** (PR #949 / Issue #946 / `e3d2f80`): `issue-lifecycle-orchestrator.sh` の F4 修正で、同一 pane 出力に対する Pattern 1 (`^[1-9]\.`) が strict 形式、Pattern 2 (`^[[:space:]]*[1-9][0-9]*[.):])`) が leading-space 許容形式になっており、インデント付き出力で Pattern 1 が不一致 → Pattern 2 が誤分類するバグが発生した。

### BAD: 同一 input への複数 pattern で ^ 直後の形式が異なる

```bash
# BAD: Pattern 1 は strict（先頭スペースを許容しない）
if [[ "$pane_output" =~ ^[1-9]\.\ (Yes,\ proceed|No,\ go\ back) ]]; then
  # → インデント付き出力では不一致

# BAD: Pattern 2 は leading-space 許容（同一 source なのに形式が違う）
elif [[ "$pane_output" =~ ^[[:space:]]*[1-9][0-9]*[.):] ]]; then
  # → スペース付きでもマッチするため、Pattern 1 を抜けたものを誤捕捉する
fi
```

### GOOD: 全パターンを `^[[:space:]]*` 形式で統一（leading-space 許容）

```bash
# GOOD: 両パターンともに leading-space を許容することで一貫性を保つ
if [[ "$pane_output" =~ ^[[:space:]]*[1-9]\.\ (Yes,\ proceed|No,\ go\ back) ]]; then
  : # 正常分岐
elif [[ "$pane_output" =~ ^[[:space:]]*[1-9][0-9]*[.):] ]]; then
  : # menu 検出分岐
fi
```

### GOOD: 全パターンを strict `^` 形式で統一（leading-space を事前除去）

```bash
# GOOD: input を trim してから strict パターンを適用する
trimmed="${pane_output#"${pane_output%%[![:space:]]*}"}"  # 先頭スペース除去
if [[ "$trimmed" =~ ^[1-9]\.\ (Yes,\ proceed|No,\ go\ back) ]]; then
  : # 正常分岐
elif [[ "$trimmed" =~ ^[1-9][0-9]*[.):] ]]; then
  : # menu 検出分岐
fi
```

**レビュー観点**: 同一 input source に対する複数 `grep -E` / `=~` パターンの `^` 直後の character class（`[[:space:]]*` の有無）を比較し、形式が混在している場合は flag する。

## 7. recursive glob (`**`) と globstar 設定

bash の `**` パターン（recursive glob）は `shopt -s globstar` を有効化していなければ通常の `*` と同等に解釈され、ディレクトリを跨いだ再帰展開が行われない。`set -euo pipefail` 環境で `**/*.py` をリテラルパスとして渡した `if grep ... "$DIR"/**/*.py 2>/dev/null; then` 構文では、grep が exit 2（ファイル不在）を返すが `2>/dev/null` でエラーが抑制され、`if` 分岐が偽となって処理がスキップされる（サイレント失敗）。

**Why** (Issue #1081 / `plugins/twl/scripts/tech-stack-detect.sh:54` / commit `6d9bffa`): `tech-stack-detect.sh` で `grep -rql ... "$PROJECT_ROOT"/**/*.py` を `shopt -s globstar` なしに使用しており、リテラルの `**/*.py` パスとして展開されて FastAPI 検出が一切 fire しないバグが顕在化した。`grep -rql --include='*.py' "$pattern" "$PROJECT_ROOT"` 形式へ修正することで再帰探索 + 拡張子フィルタを明示している。

### BAD: globstar 未設定で `**/*.ext` を使う

```bash
# BAD: shopt -s globstar なし — **/*.py がリテラルパスとして展開される
# grep が exit 2（ファイル不在）を返すが 2>/dev/null で抑制 → if 偽分岐でサイレント失敗
if grep -rql 'from fastapi' "$PROJECT_ROOT"/**/*.py 2>/dev/null; then
  LANGUAGE_HINTS["fastapi"]=1
fi
```

### GOOD: `--include` で再帰検索を明示する

```bash
# GOOD: grep -r の再帰探索 + --include で拡張子フィルタ — globstar 設定不要
if grep -rql --include='*.py' 'from fastapi' "$PROJECT_ROOT" 2>/dev/null; then
  LANGUAGE_HINTS["fastapi"]=1
fi
```

### GOOD: `find ... -name '*.ext'` で明示的に列挙する

```bash
# GOOD: find で再帰列挙してから処理する — POSIX 互換、globstar 不要
while IFS= read -r f; do
  : # process "$f"
done < <(find "$PROJECT_ROOT" -type f -name '*.py')
```

### GOOD: 必要な範囲だけ `shopt -s globstar` を局所有効化する（最終手段）

```bash
# GOOD: サブシェル内で globstar を有効化し親シェルへ波及させない
process_py_files() (
  shopt -s globstar nullglob
  for f in "$PROJECT_ROOT"/**/*.py; do
    : # process "$f"
  done
)
```

> `nullglob` の併用も推奨（マッチ 0 件で iterable が空になる挙動を保証）。

**レビュー観点**: bash スクリプトで `$VAR/**/*.ext` 形式の glob 展開を見つけた場合、同ファイル内（または source 元のスクリプト）で `shopt -s globstar` が有効化されているかを確認する。未設定であれば、`grep -rql --include='*.ext' ... "$DIR"` または `find "$DIR" -name '*.ext'` への置換を提案する。
