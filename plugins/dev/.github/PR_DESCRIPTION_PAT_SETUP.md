## PAT セットアップ手順（手動実施）

### 1. PAT 作成

GitHub Settings > Developer settings > Personal access tokens > Fine-grained tokens

- Token name: `ADD_TO_PROJECT_PAT`
- Expiration: 任意（推奨: 1 year）
- Repository access: All repositories（または対象3リポを個別指定）
- Permissions:
  - **Repository permissions**: Issues (Read), Metadata (Read)
  - **Account permissions**: Projects (Read and write)

または Classic PAT の場合:
- Scopes: `project`, `repo`

### 2. Secret 登録（3リポ全て）

以下の各リポジトリで Settings > Secrets and variables > Actions > New repository secret:

| リポジトリ | Secret 名 | 値 |
|---|---|---|
| `shuu5/loom-plugin-dev` | `ADD_TO_PROJECT_PAT` | 上記で作成した PAT |
| `shuu5/loom` | `ADD_TO_PROJECT_PAT` | 同上 |
| `shuu5/loom-plugin-session` | `ADD_TO_PROJECT_PAT` | 同上 |

または CLI で一括登録:

```bash
echo "<PAT_VALUE>" | gh secret set ADD_TO_PROJECT_PAT --repo shuu5/loom-plugin-dev
echo "<PAT_VALUE>" | gh secret set ADD_TO_PROJECT_PAT --repo shuu5/loom
echo "<PAT_VALUE>" | gh secret set ADD_TO_PROJECT_PAT --repo shuu5/loom-plugin-session
```
