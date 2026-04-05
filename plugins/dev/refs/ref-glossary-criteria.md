# glossary 用語登録判断基準

co-issue Step 1.5 で LLM が未登録用語を自動分類するための判断基準。

## 3軸判断基準

| 軸 | 登録すべき | 登録不要 |
|---|---|---|
| **Context 横断性** | 複数の Bounded Context で使用される（`architecture/domain/context-map.md` で確認） | 1つの Bounded Context 内で完結する |
| **ドメイン固有性** | このプラグイン（plugin-dev）のドメイン固有概念 | プラットフォーム・インフラ・汎用 DDD 用語 |
| **定着度** | コードベース・Issue・PR で定着済み（複数ファイルで使用 or 複数 Issue/PR で言及） | 提案段階の新概念（今回初出 or 単一箇所のみ） |

## 判定ロジック

```
3軸のうち 2軸以上で「登録すべき」に該当 → 登録推奨
1軸以下で「登録すべき」に該当        → 登録不要
```

### context-map.md 不在時のフォールバック

ARCH_CONTEXT に `context-map.md` が含まれない場合:
- **Context 横断性** の評価を「不明」として1軸分マイナス扱い
- 残り2軸（ドメイン固有性・定着度）が **両方**「登録すべき」の場合のみ登録推奨とする

## MUST/SHOULD 振り分け基準

| 分類 | 条件 |
|---|---|
| **MUST** | Context 横断性あり（複数 Bounded Context で使用確認済み） |
| **SHOULD** | Context 横断性なし/不明（ドメイン固有性 + 定着度で推奨） |

## 具体例

### 登録推奨

| 用語 | Context 横断性 | ドメイン固有性 | 定着度 | 分類 |
|---|---|---|---|---|
| `findings` | ○（PR Cycle + Issue Mgmt） | ○ | ○（複数ファイルで使用） | MUST |
| `change-id` | ○（workflow-setup + pr-cycle） | ○ | ○（複数スキルで参照） | MUST |
| `ARCH_CONTEXT` | ○（co-issue + workflow-setup） | ○ | ○（複数スキルで参照） | MUST |

### 登録不要

| 用語 | Context 横断性 | ドメイン固有性 | 定着度 | 不要理由 |
|---|---|---|---|---|
| `maxTurns` | ✗ | ✗（プラットフォームパラメータ） | ✗ | 3軸すべて不該当 |
| `scope_files` | ✗（co-issue 内部のみ） | △ | ✗（単一スキル内） | 1軸以下 |
| バジェット制御 | 不明 | ○ | ✗（提案段階） | フォールバック適用で残り1軸のみ |
| `IS_AUTOPILOT` | ✗（workflow-setup 内部変数） | ✗（実装レベル変数） | ○（複数スキルで使用） | 1軸以下 |

## 適用スコープ

このリファレンスは **co-issue Step 1.5 での用語登録判断** に使用する。他のコンポーネントが glossary 照合を行う場合は、このリファレンスを DCI で Read して同一基準を適用できる。

merge-gate の glossary drift 検出（`worker-architecture` 責務）とは独立しており、merge-gate は本リファレンスを使用しない。
