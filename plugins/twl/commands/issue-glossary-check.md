# /twl:issue-glossary-check - glossary 照合（architecture drift 通知）

**通知レベル: INFO（非ブロッキング）** — merge-gate の WARNING（ブロッキング可）とは異なり、Issue 作成フローを止めない。完全一致のみを対象とし、略語・表記ゆれは照合しない。

## 入力

- `ARCH_CONTEXT`: Phase 1 で読み込んだ architecture context（vision.md, context-map.md, glossary.md）

## スキップ条件

`architecture/domain/glossary.md` が存在しない場合はこのコマンド全体をスキップする。

## フロー（MUST）

1. `architecture/domain/glossary.md` を読み込み、`### MUST 用語` セクションのテーブルから用語名（列1）を抽出する
2. `.controller-issue/explore-summary.md` から主要用語・概念名を抽出する
3. explore-summary.md から抽出した用語のうち、MUST 用語テーブルに存在しない（未登録の）用語を列挙する（部分一致・略語は除外）
4. 不一致用語が 1 件以上あれば INFO レベルで以下を通知する（3軸判断はステップ6で行う）:
   > `[INFO] この概念は architecture spec に未定義です: <用語1>, <用語2>, ... （以降で登録判断を実施します）`
5. `refs/ref-glossary-criteria.md` を DCI で Read する（ARCH_CONTEXT に含まれない個別 ref のため個別に Read すること）
6. 各未登録用語を3軸で判断する:
   - **Context 横断性**: ARCH_CONTEXT 内の `architecture/domain/context-map.md` を参照して複数 Bounded Context での使用有無を確認する。context-map.md が ARCH_CONTEXT に含まれない場合は「不明」として1軸分マイナス扱い（残り2軸が両方「登録すべき」の場合のみ登録推奨）
   - **ドメイン固有性**: プラットフォーム由来・インフラ用語・汎用 DDD 用語でないか判断する
   - **定着度**: コードベースでの使用箇所を確認し、複数ファイルで使用または複数 Issue/PR で言及されているか判断する
7. **3軸判断で2軸以上該当した用語のみ**を登録推奨候補として以下のテーブルを表示し AskUserQuestion でユーザー承認を求める:

   | 用語 | 定義案 | Context | MUST/SHOULD | 判断理由 |
   |---|---|---|---|---|
   | ... | ... | ... | ... | ... |

   承認された用語の `glossary.md` 追記テキストをテキストで提示する。**ユーザーが自身で Edit して追記する**（LLM による自動書き込みは禁止）。
8. 登録推奨なし or ユーザーが全拒否 → フローを停止せずに呼び出し元に制御を返す（非ブロッキング）
