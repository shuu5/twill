## Context

`loom chain generate` は現在 `<name>` と `<name> --write` のみ対応。chain-driven アーキテクチャの運用では、`--write` 後のファイル手動編集によるドリフト検出と、複数 chain の一括操作が不可欠。`sync-docs --check` が同様のパターンを実装済みで、設計を踏襲する。

既存の `handle_chain_subcommand()` は argparse で `chain_name`（必須）と `--write` を受け取る。`--check` と `--all` を追加する際、`chain_name` を optional に変更し、`--all` との排他制御が必要。

## Goals / Non-Goals

**Goals:**

- `--check` による Template A のドリフト検出（正規化ハッシュ比較 + unified diff）
- `--all` による全 chain 一括操作（stdout / --write / --check）
- CI/Hook 親和性（exit code: 0 = ok, 1 = drift）
- `sync-docs --check` と一貫した UX

**Non-Goals:**

- Template B の --check 対応（#32 スコープ）
- `--filter` や glob パターンによる chain 選択
- `--fix` や自動修正モード

## Decisions

### D1: argparse 構造 → chain_name を nargs='?' に変更

`chain_name` を `nargs='?'`（optional positional）に変更。`--all` 指定時は chain_name 不要。両方指定時はエラー。

```python
parser.add_argument('chain_name', nargs='?', default=None)
parser.add_argument('--write', action='store_true')
parser.add_argument('--check', action='store_true')
parser.add_argument('--all', action='store_true')
```

排他バリデーション:
- `--all` と `chain_name` が両方 → エラー
- `--all` も `chain_name` もなし → エラー
- `--check` と `--write` が両方 → エラー

### D2: --check の正規化 → trailing whitespace 除去 + LF 統一

```python
def _normalize_for_check(text: str) -> str:
    lines = text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
    return '\n'.join(line.rstrip() for line in lines)
```

正規化後のハッシュ比較で一致判定。不一致時は `difflib.unified_diff` で差分生成。

### D3: --check の対象セクション抽出 → 既存の正規表現を流用

`chain_generate_write()` で使用している `r'^##\s+(?:チェックポイント|Checkpoint).*$'` を流用してセクション抽出。セクション不在は DRIFT として扱う（--write 未実行状態）。

### D4: --all の実装 → chain_generate を反復呼び出し

`deps.get('chains', {})` から全 chain 名を取得し、各 chain に対して既存の `chain_generate()` → `chain_generate_print()` / `chain_generate_write()` / 新規 `chain_generate_check()` を呼び出す。

chains が 0 件の場合: `"0 chains found"` + exit 0。

### D5: --all --check の出力形式 → サマリー先行 + diff 末尾

```
chain: workflow-setup
  skills/workflow-setup/SKILL.md   ... ok
  commands/worktree-create.md      ... ok

chain: workflow-pr-cycle
  commands/phase-review.md         ... DRIFT
  commands/fix-phase.md            ... DRIFT

Summary: 2/5 chains ok, 2 files drifted in 1 chain.
Run 'loom chain generate --all --write' to fix.

=== Diff: commands/phase-review.md ===
--- expected
+++ actual
...
```

### D6: 新規関数の追加

| 関数 | 責務 |
|------|------|
| `chain_generate_check()` | 単一 chain の Template A ドリフト検出 |
| `_normalize_for_check()` | テキスト正規化（trailing ws + LF） |
| `_extract_checkpoint_section()` | ファイルからチェックポイントセクション抽出 |

`chain_generate_check()` は `chain_generate_write()` と並列の関数として配置（write のロジックを分岐させない）。

## Risks / Trade-offs

- **正規化の限界**: trailing whitespace と改行コード以外のエディタ由来差異（BOM 等）は非対応。必要時に正規化ルールを追加可能
- **Template A のみ対応**: #32 完了まで Template B のドリフトは検出できない。Issue body に明記済み
- **--all のパフォーマンス**: chain 数が多い場合に逐次処理となるが、現実的な chain 数（<20）では問題なし
