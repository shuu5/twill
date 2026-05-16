# ssot-design 廃案 3 案 (rollback 保持)

twill plugin の chain SSoT 統合設計検討の過程で、最終的に採用された案 4 (`registry.yaml` 統合 SSoT、`architecture/spec/ssot-design.html` で normative 化) に至るまでに検討された 3 つの廃案を、判断経緯の歴史的記録として保存する。

本 file は **archive scope** であり、現状仕様 (normative) ではない。新規 ADR から本 file を参照する場合は decision rationale の補強 reference として扱う。

## 案 1 (廃案): `deps.yaml` SSoT

`chain.py` + `chain-steps.sh` を全廃し、`deps.yaml` から chain 定義を生成する案。

### Pros

- YAML editing は人間にとって直感的
- yamllint integration
- コメントサポート

### Cons

- `deps.yaml` v3.0 既存巨大化 (~250 行)
- bash dispatch logic を YAML 内 inline は無理
- `chain.py` を捨てると Python validation も再実装が必要

## 案 2 (廃案): `chain.py` SSoT

`chain-steps.sh` + `deps.yaml.chains` を全廃し、Python (`chain.py`) を SSoT とする案。

### Pros

- 既存 `chain.py` に dispatch / metadata / export が集約
- Python type hint で integrity を強化可能

### Cons

- bash 側 (`chain-runner.sh`) から `chain.py` 直接呼び出し不可
- 引き続き `chain-steps.sh` 経由 export 必要
- 本質は「dispatch + metadata の 2 重 SSoT」のままで mitigation

## 案 3 (廃案): `step.sh` 単一 SSoT

1 step = 1 `steps/<name>.sh` file = SSoT、`_verify_<name>` 関数で post-verify rule 同 file 内に保有する案。

### Pros

- 「分散 SSoT」原則に最も忠実
- post-verify rule が step file 内に inline

### Cons

- `step` は forbidden 一般語、`atomic` が canonical
- `step.sh framework` の `step::run` bash 呼び出しは公式 skill 機構 (Skill tool + atomic SKILL.md) と二重 framework になる
- vocabulary / types.yaml と独立した別 SSoT を作るため SSoT 多重化解消にならない

## 採用された案 4 への進化

3 廃案の cons を統合的に解消するため、`plugins/twl/registry.yaml` 1 file を 5 section (`glossary` / `components` / `chains` / `hooks` + `monitors` / `integrity_rules`) の Authority SSoT として位置づける**案 4** を採用した。詳細仕様は `architecture/spec/ssot-design.html` および `architecture/spec/registry-schema.html` を参照。
