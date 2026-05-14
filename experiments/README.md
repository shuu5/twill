# EXP framework

twill plugin radical rebuild の実機検証実験 (EXP) infrastructure。`architecture/spec/twill-plugin-rebuild/experiment-index.html` で listing される 38 EXP を機械的に実行する。

## Layout

- `gen-manifest.py` — `experiment-index.html` を parse して `manifest.json` を生成 (stdlib only)
- `run-all.sh` — `manifest.json` を読み bats 等を dispatch、result を `.audit/<run-id>/experiments/EXP-NNN.json` に出力
- `manifest.json` — generated artifact (gitignored)

EXP fixtures は `test-fixtures/experiments/<category>/EXP-NNN-<short>.bats` 規約で配置。category は A-N (詳細は `experiment-index.html` の category note 参照)。

## Usage

```bash
# manifest 再生成 + bats unit 一括実行
bash experiments/run-all.sh --category bats-unit

# dry-run (実行せず listing のみ)
bash experiments/run-all.sh --category bats-unit --dry-run
```

## Related

- `architecture/spec/twill-plugin-rebuild/experiment-index.html` (Authority SSoT)
- `architecture/spec/twill-plugin-rebuild/sandbox-experiment.html` (上位 architecture)
- `test-fixtures/experiments/common.bash` (bats helper)
