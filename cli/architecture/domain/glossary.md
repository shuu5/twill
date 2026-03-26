## Glossary

| 用語 | 定義 | Context |
|------|------|---------|
| deps.yaml | プラグイン構造の SSOT。全コンポーネント定義を含む | Plugin Structure |
| types.yaml | 型ルールの SSOT。can_spawn/spawnable_by を定義 | Type System |
| Component | プラグインの構成単位（.md ファイル）| Plugin Structure |
| Chain | v3.0 のステップ順序定義。deps.yaml の chains セクション | Chain Management |
| Template A | chain generate が生成するチェックポイントセクション | Chain Management |
| Template B | chain generate が生成する called-by frontmatter | Chain Management |
| spawnable_by | あるコンポーネントを呼び出せる型の制約 | Type System |
| can_spawn | あるコンポーネントが呼び出せる型の制約 | Type System |
| deep-validate | frontmatter/body の詳細整合性検証 | Validation |
| audit | Loom 準拠度の5セクション監査 | Validation |
