## Step 0.5: explore-summary 必須チェック

引数から Issue `#N` を取得し、explore-summary の存在を確認する。

### refine モードの場合

`refine_mode=true` の場合、explore-summary チェック**失敗での停止**はスキップする。ただし explore-summary が存在する場合は読み込んで補助情報として活用する:

```bash
# explore-summary があれば読み込み（refine では必須ではないが、あれば活用）
for _n in <targets の各 Issue 番号>; do
  if twl explore-link check "$_n" 2>/dev/null; then
    mkdir -p ".controller-issue/${SESSION_ID}"
    twl explore-link read "$_n" >> ".controller-issue/${SESSION_ID}/explore-summary.md"
    echo "--- (Issue #${_n} explore-summary end) ---" >> ".controller-issue/${SESSION_ID}/explore-summary.md"
  fi
done
```

以降の Phase 2 で `.controller-issue/<session-id>/explore-summary.md` が存在すれば、改善点の特定に活用する。

1. **既存 Issue body の読み込み**: Step 0 で取得した各 Issue の body・labels・title を確認
2. **改善点の探索**: コードベース（Read/Grep/Glob）と architecture context を参照し、既存 Issue body の改善点を特定:
   - テンプレート準拠性: 必須セクション（## 概要 / ## AC / ## スコープ / ## 技術メモ）の有無、AC が `[ ]` チェックリスト形式で機械検証可能か
   - 技術的正確性: Issue body が参照するファイルパス・関数名・型名が現在のコードベースに存在するか（Grep/Glob で検証）
   - スコープの適切性: 1 PR で完結可能な粒度か（目安: 変更ファイル数 10 以下）、逆に複数 Issue に分割すべきか
3. **draft.md の生成**: 改善後の body を Issue テンプレート準拠フォーマットで生成
4. Phase 2 へ進む

### 通常モードの場合

```bash
twl explore-link check <N>
```

- **exit 0（存在）**: `twl explore-link read <N>` で summary を読み込み、`EXPLORE_SUMMARY` として保持。`.controller-issue/<session-id>/explore-summary.md` にコピーして Phase 2 へ進む
- **exit 1（不在）**: 「Issue #N に explore-summary がありません。先に `/twl:co-explore #N` を実行してください」と表示して停止

`architecture/` が存在する場合、vision.md・context-map.md・glossary.md を Read して `ARCH_CONTEXT` として保持（不在はスキップ）。

`mkdir -p .controller-issue/<session-id>`
