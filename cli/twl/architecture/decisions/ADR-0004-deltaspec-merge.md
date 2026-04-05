## ADR-0004: deltaspec を twl に統合

## Status

Accepted

## Context

twl と deltaspec は TWiLL フレームワークの2つの独立 CLI として存在していた。

- **twl**: Python 6,074行 + bash 227行。プラグイン構造の検証・可視化
- **deltaspec**: bash 900行。openspec/changes/ のライフサイクル管理

deltaspec は bash で YAML 解析・JSON 生成を自作しており、保守性・テスタビリティに問題があった。
両ツールは同一ドメイン（TWiLL フレームワークの開発ワークフロー）に属し、技術スタック統一の利点が大きい。

## Decision

deltaspec の全機能を twl に統合する。

- サブコマンド体系: `twl spec <cmd>`（new, status, list, archive, validate, instructions）
- 新しい Bounded Context「Spec Management」を追加
- 統合完了後、`cli/deltaspec/` ディレクトリは即座に削除
- 移行期間や deprecated 警告は設けない（利用者が限定的）

### コマンドマッピング

| deltaspec | twl (統合後) |
|-----------|-------------|
| `deltaspec new change <name>` | `twl spec new <name>` |
| `deltaspec status --change <name>` | `twl spec status <name>` |
| `deltaspec list` | `twl spec list` |
| `deltaspec archive <name>` | `twl spec archive <name>` |
| `deltaspec validate [name]` | `twl spec validate [name]` |
| `deltaspec instructions <artifact>` | `twl spec instructions <artifact>` |

### インターフェース簡略化

統合に際し、deltaspec の冗長な CLI インターフェースを整理する:
- `--change <name>` フラグ → 位置引数 `<name>` に統一
- `--schema` フラグ → 削除（spec-driven 固定、将来拡張時に再追加）

## Consequences

**良い点:**
- CLI が1つに統一。ユーザーは `twl` だけ覚えればよい
- PyYAML, json, pathlib 等を共有。bash の自作パーサーが不要に
- pytest で統合テスト可能
- spec/ モジュールは core/plugin.py の Plugin 構造を参照でき、将来的に spec と deps.yaml の連携が可能

**悪い点:**
- twl の責務範囲が広がる（構造検証 + 仕様管理）
- deltaspec コマンドに慣れたワークフローの変更が必要

**緩和策:**
- `twl spec` サブコマンドで名前空間を分離し、責務の混在を防ぐ
- コマンドマッピングは直感的（`deltaspec validate` → `twl spec validate`）で学習コストは低い
