## 1. pyproject.toml 作成

- [ ] 1.1 `cli/twl/pyproject.toml` を作成する（name、version、requires-python、dependencies、optional-dependencies、scripts、build-system を含む）
- [ ] 1.2 `[project.dependencies]` に PyYAML を定義する
- [ ] 1.3 `[project.optional-dependencies]` に tiktoken と rich を定義する
- [ ] 1.4 `[project.scripts]` に `twl = "twl.cli:run"` を定義する

## 2. src/twl/ ディレクトリ構造作成

- [ ] 2.1 `cli/twl/src/twl/__init__.py` を作成する
- [ ] 2.2 `cli/twl/src/twl/__main__.py` を作成する（`from twl.cli import run; run()` を呼び出す）
- [ ] 2.3 `cli/twl/src/twl/cli.py` を作成する（twl-engine.py の main() に委譲する `run()` 関数を実装）

## 3. 動作確認

- [ ] 3.1 コンテナ内で `pip install -e .` を実行し成功することを確認する
- [ ] 3.2 `python3 -m twl --help` で既存ヘルプが表示されることを確認する
- [ ] 3.3 `python3 -m twl check` 等の既存コマンドが動作することを確認する
- [ ] 3.4 `pytest tests/` が引き続き通過することを確認する
