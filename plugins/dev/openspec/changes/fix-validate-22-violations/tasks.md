## 1. deps.yaml の external 参照を cross-plugin 参照に置換

- [x] 1.1 autopilot-poll の calls から `external`/`path`/`optional`/`note` エントリを除去し `- script: session:session-state` に置換
- [x] 1.2 autopilot-phase-execute の calls から同様に置換
- [x] 1.3 crash-detect の calls から同様に置換
- [x] 1.4 health-check の calls から同様に置換

## 2. 検証

- [x] 2.1 `loom validate` が Violations 0 で PASS することを確認
- [x] 2.2 `loom check` が Missing 0 を維持することを確認
