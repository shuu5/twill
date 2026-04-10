## Context

`twl spec new` は `.deltaspec.yaml` に `schema` と `created` のみを書き込む。`autopilot-orchestrator.sh` と Python 版 `orchestrator.py` は archive 対象の change を `issue: <N>` フィールドの grep で検索する。フィールドが存在しないため常に 0 件ヒットとなり archive されない。

`change-propose.md` の Step 0 では手動で `echo "issue: <N>"` を補完しているが、`twl spec new` 自体が出力しないため、コマンド経由でない場合や将来の変更で欠落が発生し得る。

## Goals / Non-Goals

**Goals:**
- `twl spec new "issue-<N>"` 実行時に `.deltaspec.yaml` へ `issue: <N>` を自動付与する
- orchestrator（sh/py 両版）が `issue:` フィールドの有無に関わらず `name: issue-<N>` パターンでも change を検出できるようにする
- 後方互換性を保つ（既存の `.deltaspec.yaml` で `issue:` なしのものも引き続き archive 可能）

**Non-Goals:**
- `issue:` フィールドがない既存 change の一括マイグレーション
- `issue:` 以外のフィールドの自動補完
- 複数 issue を参照する change のサポート変更

## Decisions

### 1. spec/new.py: issue フィールドの自動付与

name が `issue-\d+` パターンにマッチする場合、`.deltaspec.yaml` に `issue: <N>` を追加する。

```python
_ISSUE_RE = re.compile(r"^issue-(\d+)$")

m = _ISSUE_RE.match(name)
issue_line = f"issue: {m.group(1)}\n" if m else ""
deltaspec_yaml.write_text(
    f"schema: spec-driven\ncreated: {date.today().isoformat()}\n"
    f"name: {name}\nstatus: pending\n{issue_line}",
    encoding="utf-8",
)
```

**Rationale**: `name` と `status` も同時に補完することで `change-propose.md` の Step 0 での手動補完を不要にし、DRY を保つ。

### 2. orchestrator フォールバック（sh 版）

```bash
# プライマリ: issue: フィールドで検索
while IFS= read -r yaml_path; do
  ...
done < <(grep -rl "^issue: ${issue}$" "$changes_dir" --include=".deltaspec.yaml" 2>/dev/null || true)

# フォールバック: name: issue-<N> パターンで検索
if [[ "$found" == "false" ]]; then
  while IFS= read -r yaml_path; do
    ...
  done < <(grep -rl "^name: issue-${issue}$" "$changes_dir" --include=".deltaspec.yaml" 2>/dev/null || true)
fi
```

### 3. orchestrator フォールバック（py 版）

```python
# プライマリ: issue: フィールド
if f"\nissue: {issue}\n" in content or content.startswith(f"issue: {issue}\n"):
    found = True; ...
# フォールバック: name: issue-<N>
elif f"\nname: issue-{issue}\n" in content or content.startswith(f"name: issue-{issue}\n"):
    found = True; ...
```

### 4. change-propose.md: issue フィールドの削除（Step 0 補完の簡素化）

`twl spec new` が自動付与するため、Step 0 の `echo "issue: <N>"` は不要となる。ただし削除せず冪等性を保つコメントとして残すか、完全削除するかはスコープ外とする（本 Issue のスコープは detection 修正）。

## Risks / Trade-offs

- **フォールバックの二重処理リスク**: `issue:` と `name:` 両方が一致する change（= 新フォーマット）は二重 archive されない。`found=true` で早期終了するため問題なし。
- **name パターンの偽マッチ**: `name: issue-<N>` は `issue-\d+` 以外の命名規則と衝突しない（専用プレフィックス）。
- **change-propose.md の補完処理**: Step 0 で `echo "name: issue-<N>"` を行う場合、`twl spec new` 後に重複付与される。`twl spec new` 側で付与するなら change-propose の補完は削除すべきだが、今回はフォールバック追加のみに留め、互換性を優先する。
