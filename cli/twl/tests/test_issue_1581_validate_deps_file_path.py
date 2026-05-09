"""Tests for Issue #1581: twl_validate_deps_handler が file_path 入力を受け付ける (RED フェーズ).

TDD RED フェーズ用テストスタブ。
実装前は全テストが FAIL する（意図的 RED）。

AC 一覧:
- AC1: _resolve_plugin_root ヘルパーが twl_validate_deps_handler 冒頭で呼ばれる
- AC2: _resolve_plugin_root が file 入力時に親 dir から deps.yaml を探索する
- AC3: dir 入力 + deps.yaml あり → そのまま返す
- AC4: dir 入力 + deps.yaml なし → 親方向 traversal で探索
- AC5: _load_plugin_ctx の is_file() ブランチは残す（変更しない）
- AC6: _resolve_plugin_root が None 返却時 → _load_plugin_ctx 呼ばず skip envelope を early-return
- AC7: skip envelope の構造: {"ok": true, "skipped": true, "reason": "non-plugin-file", "input": <input>, "exit_code": 0}
- AC8: skip 時は ValueError を raise しない / stderr に "is not a directory" / "Failed to load plugin context" を出力しない
- AC9: 以下のケースで skip されること（AC12, AC13 参照）
- AC10: test_validate_deps_handler_accepts_file_path_in_plugin_root_dir
- AC11: test_validate_deps_handler_accepts_file_path_in_plugin_subdir
- AC12: test_validate_deps_handler_skips_non_plugin_file_outside_repo
- AC13: test_validate_deps_handler_skips_file_in_repo_without_deps_yaml
- AC14: test_validate_deps_handler_directory_passthrough_unchanged
- AC15: bats test は MCP サーバー起動不要、python3 -c で直接呼び出し
- AC16: plugin 内 file_path → exit_code=0, skipped フィールドなし, stderr エラーなし
- AC17: plugin 外 tmp file → exit_code=0, skipped=true, stderr エラーなし
- AC18: twl_validate_deps_handler の docstring に _resolve_plugin_root 説明を明記
- AC19: _load_plugin_ctx は変更しない
"""

import inspect
import subprocess
import sys
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
WORKTREE_ROOT = TWL_DIR.parent.parent

# テストで使う実在パス
PLUGIN_ROOT_FILE = WORKTREE_ROOT / "plugins" / "twl" / "README.md"
PLUGIN_SUBDIR_FILE = WORKTREE_ROOT / "plugins" / "twl" / "skills" / "co-issue" / "SKILL.md"
REPO_NO_DEPS_FILE = WORKTREE_ROOT / "architecture" / "vision.md"
PLUGIN_ROOT_DIR = WORKTREE_ROOT / "plugins" / "twl"


# ---------------------------------------------------------------------------
# AC1: _resolve_plugin_root が tools.py に存在すること
# ---------------------------------------------------------------------------

class TestAC1ResolvePluginRootExists:
    """AC1: _resolve_plugin_root ヘルパーが tools.py に定義されていること."""

    def test_ac1_resolve_plugin_root_function_exists(self):
        # AC: _resolve_plugin_root が private helper として tools.py に定義されていること
        # RED: 未実装のため AttributeError
        from twl.mcp_server import tools
        assert hasattr(tools, "_resolve_plugin_root"), (
            "_resolve_plugin_root が tools.py に定義されていない (AC1 未実装)"
        )
        fn = getattr(tools, "_resolve_plugin_root")
        assert callable(fn), "_resolve_plugin_root は callable でない (AC1 未実装)"

    def test_ac1_resolve_plugin_root_called_in_handler(self):
        # AC: twl_validate_deps_handler の実装内で _resolve_plugin_root を呼び出すこと
        # RED: 未実装のため該当コードがない
        tools_src = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
        content = tools_src.read_text(encoding="utf-8")
        assert "_resolve_plugin_root" in content, (
            "tools.py に _resolve_plugin_root が存在しない (AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2: _resolve_plugin_root のファイル入力時の動作
# ---------------------------------------------------------------------------

class TestAC2ResolvePluginRootFileInput:
    """AC2: file 入力時に p.parent から deps.yaml を探索する."""

    def test_ac2_file_input_resolves_to_parent_dir(self):
        # AC: 入力が file の場合、p.parent から上方向に deps.yaml を探索する
        # RED: _resolve_plugin_root が未実装のため ImportError/AttributeError
        from twl.mcp_server.tools import _resolve_plugin_root
        from pathlib import Path

        # plugins/twl/README.md → plugins/twl/ (deps.yaml あり)
        assert PLUGIN_ROOT_FILE.is_file(), f"テスト用ファイルが存在しない: {PLUGIN_ROOT_FILE}"
        result = _resolve_plugin_root(PLUGIN_ROOT_FILE)
        assert result is not None, (
            f"_resolve_plugin_root({PLUGIN_ROOT_FILE}) が None を返した (AC2 未実装)"
        )
        assert result.is_dir(), f"_resolve_plugin_root の戻り値が dir でない: {result}"
        assert (result / "deps.yaml").exists(), (
            f"返却された dir に deps.yaml が存在しない: {result}"
        )

    def test_ac2_file_in_subdir_traverses_to_plugin_root(self):
        # AC: サブディレクトリのファイル入力時、上方向に deps.yaml を探索して plugin root を返す
        # RED: _resolve_plugin_root が未実装
        from twl.mcp_server.tools import _resolve_plugin_root

        assert PLUGIN_SUBDIR_FILE.is_file(), f"テスト用ファイルが存在しない: {PLUGIN_SUBDIR_FILE}"
        result = _resolve_plugin_root(PLUGIN_SUBDIR_FILE)
        assert result is not None, (
            f"_resolve_plugin_root({PLUGIN_SUBDIR_FILE}) が None を返した (AC2 未実装)"
        )
        assert result.is_dir()
        assert (result / "deps.yaml").exists()


# ---------------------------------------------------------------------------
# AC3: dir 入力 + deps.yaml あり → そのまま返す
# ---------------------------------------------------------------------------

class TestAC3DirWithDepsYaml:
    """AC3: dir 入力かつ deps.yaml を含む場合はそのまま返す."""

    def test_ac3_dir_with_deps_yaml_returns_same_dir(self):
        # AC: dir 入力 + deps.yaml あり → そのまま返す（既存動作と同等）
        # RED: _resolve_plugin_root が未実装
        from twl.mcp_server.tools import _resolve_plugin_root

        assert PLUGIN_ROOT_DIR.is_dir()
        assert (PLUGIN_ROOT_DIR / "deps.yaml").exists()
        result = _resolve_plugin_root(PLUGIN_ROOT_DIR)
        assert result is not None
        assert result == PLUGIN_ROOT_DIR.resolve(), (
            f"dir 入力で同じ dir が返らなかった: {result} != {PLUGIN_ROOT_DIR.resolve()} (AC3 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4: dir 入力 + deps.yaml なし → 親方向 traversal
# ---------------------------------------------------------------------------

class TestAC4DirWithoutDepsYaml:
    """AC4: dir 入力かつ deps.yaml なし → 親方向 traversal で探索."""

    def test_ac4_dir_without_deps_yaml_traverses_up(self):
        # AC: dir 入力で deps.yaml がない場合、親方向に探索する
        # RED: _resolve_plugin_root が未実装
        from twl.mcp_server.tools import _resolve_plugin_root

        # plugins/twl/skills/co-issue は deps.yaml を持たないが plugins/twl が持つ
        subdir = WORKTREE_ROOT / "plugins" / "twl" / "skills" / "co-issue"
        assert subdir.is_dir()
        assert not (subdir / "deps.yaml").exists(), "テスト前提: co-issue に deps.yaml がないこと"
        result = _resolve_plugin_root(subdir)
        assert result is not None, (
            f"_resolve_plugin_root({subdir}) が None を返した (AC4 未実装)"
        )
        assert (result / "deps.yaml").exists()


# ---------------------------------------------------------------------------
# AC5: _load_plugin_ctx は変更しない
# ---------------------------------------------------------------------------

class TestAC5LoadPluginCtxUnchanged:
    """AC5: _load_plugin_ctx の既存 is_file() ロジックは変更しない."""

    def test_ac5_load_plugin_ctx_has_is_file_branch(self):
        # AC: _load_plugin_ctx の line 20-21 に is_file() → parent ロジックが残ること
        # RED: 実装者が誤って削除した場合に FAIL
        tools_src = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
        content = tools_src.read_text(encoding="utf-8")

        # _load_plugin_ctx 内に is_file() ブランチが存在することを確認
        # 注: 実装前は _resolve_plugin_root も存在しないため、現状は pass する可能性あり
        # このテストは AC5 の non-regression を保証するもの
        assert "def _load_plugin_ctx" in content, "_load_plugin_ctx が削除されている (AC5 破壊)"
        assert "is_file()" in content, (
            "_load_plugin_ctx から is_file() ブランチが削除されている (AC5 破壊)"
        )


# ---------------------------------------------------------------------------
# AC6: None 返却時に _load_plugin_ctx を呼ばず skip を early-return
# ---------------------------------------------------------------------------

class TestAC6SkipWhenNoneReturned:
    """AC6: _resolve_plugin_root が None を返す場合、_load_plugin_ctx を呼ばずに skip."""

    def test_ac6_skip_envelope_returned_for_non_plugin_file(self):
        # AC: plugin 外ファイルで handler が skip envelope を返し、ValueError を raise しない
        # RED: 実装前は ValueError が発生する
        from twl.mcp_server.tools import twl_validate_deps_handler

        tmp_file = "/tmp/twl-test-ac6-nonexistent.md"
        # 実装前は ValueError: 'is not a directory' が発生する
        result = twl_validate_deps_handler(tmp_file)
        assert result.get("skipped") is True, (
            f"skip envelope が返らなかった: {result} (AC6 未実装)"
        )


# ---------------------------------------------------------------------------
# AC7: skip envelope の構造
# ---------------------------------------------------------------------------

class TestAC7SkipEnvelopeStructure:
    """AC7: skip envelope の構造確認."""

    def test_ac7_skip_envelope_has_required_fields(self):
        # AC: {"ok": true, "skipped": true, "reason": "non-plugin-file", "input": <input>, "exit_code": 0}
        # RED: 実装前は ValueError が発生する
        from twl.mcp_server.tools import twl_validate_deps_handler

        input_path = "/tmp/twl-test-ac7-nonexistent.md"
        result = twl_validate_deps_handler(input_path)

        assert result.get("ok") is True, f"ok フィールドが True でない: {result}"
        assert result.get("skipped") is True, f"skipped フィールドが True でない: {result}"
        assert result.get("reason") == "non-plugin-file", f"reason が 'non-plugin-file' でない: {result}"
        assert result.get("exit_code") == 0, f"exit_code が 0 でない: {result}"
        assert "input" in result, f"input フィールドがない: {result}"


# ---------------------------------------------------------------------------
# AC8: skip 時は ValueError 非発生 / stderr にエラーメッセージ出力なし
# ---------------------------------------------------------------------------

class TestAC8NoErrorOnSkip:
    """AC8: skip 時は ValueError を raise せず、stderr にエラーを出力しない."""

    def test_ac8_no_value_error_on_skip(self):
        # AC: plugin 外ファイルで ValueError が発生しない
        # RED: 実装前は ValueError が発生する
        from twl.mcp_server.tools import twl_validate_deps_handler

        try:
            result = twl_validate_deps_handler("/tmp/twl-test-ac8-nonexistent.md")
        except ValueError as e:
            pytest.fail(f"ValueError が発生した (AC8 未実装): {e}")

    def test_ac8_no_error_message_in_subprocess_stderr(self):
        # AC: subprocess 経由で呼び出した際も stderr にエラーメッセージを出力しない
        # RED: 実装前は "is not a directory" が stderr に出力される
        cmd = [
            sys.executable, "-c",
            "from twl.mcp_server.tools import twl_validate_deps_handler; "
            "import json; print(json.dumps(twl_validate_deps_handler('/tmp/twl-test-ac8.md')))"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(TWL_DIR))
        assert "is not a directory" not in result.stderr, (
            f"stderr に 'is not a directory' が含まれている (AC8 未実装): {result.stderr}"
        )
        assert "Failed to load plugin context" not in result.stderr, (
            f"stderr に 'Failed to load plugin context' が含まれている (AC8 未実装): {result.stderr}"
        )


# ---------------------------------------------------------------------------
# AC10: plugin root dir 内のファイルを入力 → validate 実行（AC 本文に名前明示）
# ---------------------------------------------------------------------------

class TestAC10AcceptFileInPluginRootDir:
    """AC10: plugin root dir 直下のファイル入力 → validate 実行."""

    def test_validate_deps_handler_accepts_file_path_in_plugin_root_dir(self):
        # AC: 入力 plugins/twl/README.md → handler が plugins/twl/ を plugin_root として validate 実行
        #     → validate_deps envelope 返却（skipped フィールド無 or false）
        # RED: 実装前は ValueError: 'is not a directory' が発生する
        from twl.mcp_server.tools import twl_validate_deps_handler

        assert PLUGIN_ROOT_FILE.is_file(), f"テスト用ファイルが存在しない: {PLUGIN_ROOT_FILE}"
        result = twl_validate_deps_handler(str(PLUGIN_ROOT_FILE))

        # skip されていないこと
        assert not result.get("skipped"), (
            f"plugin 内ファイルなのに skip された: {result} (AC10 未実装)"
        )
        # validate_deps envelope が返ること
        assert result.get("ok") is not None, f"ok フィールドがない: {result}"
        assert "exit_code" in result, f"exit_code フィールドがない: {result}"
        # ValueError / "is not a directory" が発生していないことは例外が起きていない時点で保証


# ---------------------------------------------------------------------------
# AC11: plugin サブディレクトリ内のファイル入力 → 親 traversal して validate 実行
# ---------------------------------------------------------------------------

class TestAC11AcceptFileInPluginSubdir:
    """AC11: plugin サブディレクトリ内ファイル入力 → 親 traversal で validate 実行."""

    def test_validate_deps_handler_accepts_file_path_in_plugin_subdir(self):
        # AC: 入力 plugins/twl/skills/co-issue/SKILL.md → plugins/twl/ を plugin_root と判定 → validate 実行
        # RED: 実装前は ValueError が発生する
        from twl.mcp_server.tools import twl_validate_deps_handler

        assert PLUGIN_SUBDIR_FILE.is_file(), f"テスト用ファイルが存在しない: {PLUGIN_SUBDIR_FILE}"
        result = twl_validate_deps_handler(str(PLUGIN_SUBDIR_FILE))

        assert not result.get("skipped"), (
            f"plugin サブディレクトリのファイルなのに skip された: {result} (AC11 未実装)"
        )
        assert result.get("ok") is not None, f"ok フィールドがない: {result}"
        assert "exit_code" in result, f"exit_code フィールドがない: {result}"


# ---------------------------------------------------------------------------
# AC12: repo 外ファイル（/tmp）→ skip envelope
# ---------------------------------------------------------------------------

class TestAC12SkipNonPluginFileOutsideRepo:
    """AC12: /tmp 以下の一時ファイル → skip envelope."""

    def test_validate_deps_handler_skips_non_plugin_file_outside_repo(self):
        # AC: 入力 /tmp/foo.md → skip envelope（ok=True, skipped=True）。ValueError 非発生
        # RED: 実装前は ValueError が発生する
        from twl.mcp_server.tools import twl_validate_deps_handler

        # /tmp 以下は deps.yaml を持つ plugin 階層外
        input_path = "/tmp/twl-test-1581-ac12.md"
        try:
            result = twl_validate_deps_handler(input_path)
        except ValueError as e:
            pytest.fail(f"ValueError が発生した (AC12 未実装): {e}")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        assert result.get("skipped") is True, f"skipped が True でない: {result}"


# ---------------------------------------------------------------------------
# AC13: repo 内ファイルだが plugin 外（deps.yaml 祖先なし）→ skip
# ---------------------------------------------------------------------------

class TestAC13SkipFileInRepoWithoutDepsYaml:
    """AC13: repo 内だが plugin 外のファイル → skip."""

    def test_validate_deps_handler_skips_file_in_repo_without_deps_yaml(self):
        # AC: 入力 architecture/vision.md (plugin 外 top-level) → skip
        # RED: 実装前は ValueError が発生する
        from twl.mcp_server.tools import twl_validate_deps_handler

        assert REPO_NO_DEPS_FILE.is_file(), f"テスト用ファイルが存在しない: {REPO_NO_DEPS_FILE}"
        try:
            result = twl_validate_deps_handler(str(REPO_NO_DEPS_FILE))
        except ValueError as e:
            pytest.fail(f"ValueError が発生した (AC13 未実装): {e}")

        assert result.get("skipped") is True, (
            f"plugin 外ファイルが skip されなかった: {result} (AC13 未実装)"
        )


# ---------------------------------------------------------------------------
# AC14: dir 入力 → 既存動作変更なし（non-regression）
# ---------------------------------------------------------------------------

class TestAC14DirectoryPassthroughUnchanged:
    """AC14: dir 入力 → 既存動作変更なし."""

    def test_validate_deps_handler_directory_passthrough_unchanged(self):
        # AC: 入力 plugins/twl/（dir）→ 既存動作変更なし（既存 test の non-regression）
        # 実装前後ともに PASS するはず（non-regression）
        from twl.mcp_server.tools import twl_validate_deps_handler

        assert PLUGIN_ROOT_DIR.is_dir()
        result = twl_validate_deps_handler(str(PLUGIN_ROOT_DIR))

        # dir 入力は既存通り validate を実行し、skip されない
        assert not result.get("skipped"), (
            f"dir 入力なのに skip された (AC14 破壊): {result}"
        )
        assert result.get("ok") is not None, f"ok フィールドがない: {result}"
        assert "exit_code" in result, f"exit_code フィールドがない: {result}"


# ---------------------------------------------------------------------------
# AC16: bats 相当動作 - plugin 内ファイル → exit_code=0, stderr エラーなし
# ---------------------------------------------------------------------------

class TestAC16PluginFileSubprocess:
    """AC16: plugin 内 file_path を python3 -c で直接呼び出し → exit_code=0, stderr エラーなし."""

    def test_ac16_plugin_file_via_subprocess(self):
        # AC: file_path として plugins/twl/README.md を渡す
        #     → exit_code=0, stdout JSON に skipped フィールドなし（または false）
        #     → stderr に "is not a directory" / "Failed to load plugin context" を含まない
        # RED: 実装前は stderr にエラーが出力される / exit_code != 0
        assert PLUGIN_ROOT_FILE.is_file(), f"テスト用ファイルが存在しない: {PLUGIN_ROOT_FILE}"

        cmd = [
            sys.executable, "-c",
            f"from twl.mcp_server.tools import twl_validate_deps_handler; "
            f"import json; print(json.dumps(twl_validate_deps_handler({str(PLUGIN_ROOT_FILE)!r})))"
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=str(TWL_DIR))

        assert "is not a directory" not in proc.stderr, (
            f"stderr に 'is not a directory' が含まれている (AC16 未実装): {proc.stderr}"
        )
        assert "Failed to load plugin context" not in proc.stderr, (
            f"stderr に 'Failed to load plugin context' が含まれている (AC16 未実装): {proc.stderr}"
        )

        import json as _json
        try:
            result = _json.loads(proc.stdout.strip())
        except _json.JSONDecodeError:
            pytest.fail(f"stdout が JSON でない (AC16 未実装): {proc.stdout!r}")

        assert not result.get("skipped"), (
            f"plugin 内ファイルなのに skipped=true が返った (AC16 未実装): {result}"
        )
        assert result.get("exit_code") == 0, (
            f"exit_code が 0 でない (AC16 未実装): {result}"
        )


# ---------------------------------------------------------------------------
# AC17: bats 相当動作 - plugin 外 tmp file → exit_code=0, skipped=true
# ---------------------------------------------------------------------------

class TestAC17NonPluginTmpFileSubprocess:
    """AC17: plugin 外 tmp file を python3 -c で直接呼び出し → exit_code=0, skipped=true."""

    def test_ac17_non_plugin_tmp_file_via_subprocess(self):
        # AC: file_path として一時 file /tmp/twl-test-$$.md（plugin 外）を渡す
        #     → exit_code=0, stdout JSON に skipped: true を含む
        #     → stderr に error message を含まない
        # RED: 実装前は stderr にエラーが出力される
        import tempfile
        import os as _os

        with tempfile.NamedTemporaryFile(
            suffix=".md", prefix="twl-test-ac17-", dir="/tmp", delete=False
        ) as f:
            tmp_path = f.name

        try:
            cmd = [
                sys.executable, "-c",
                f"from twl.mcp_server.tools import twl_validate_deps_handler; "
                f"import json; print(json.dumps(twl_validate_deps_handler({tmp_path!r})))"
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True, cwd=str(TWL_DIR))

            assert "is not a directory" not in proc.stderr, (
                f"stderr に 'is not a directory' が含まれている (AC17 未実装): {proc.stderr}"
            )
            assert "Failed to load plugin context" not in proc.stderr, (
                f"stderr に 'Failed to load plugin context' が含まれている (AC17 未実装): {proc.stderr}"
            )

            import json as _json
            try:
                result = _json.loads(proc.stdout.strip())
            except _json.JSONDecodeError:
                pytest.fail(f"stdout が JSON でない (AC17 未実装): {proc.stdout!r}")

            assert result.get("skipped") is True, (
                f"plugin 外ファイルで skipped=true が返らなかった (AC17 未実装): {result}"
            )
            assert result.get("exit_code") == 0, (
                f"exit_code が 0 でない (AC17 未実装): {result}"
            )
        finally:
            _os.unlink(tmp_path)


# ---------------------------------------------------------------------------
# AC18: docstring に _resolve_plugin_root の説明が明記されていること
# ---------------------------------------------------------------------------

class TestAC18DocstringUpdated:
    """AC18: twl_validate_deps_handler の docstring に _resolve_plugin_root 説明を明記."""

    def test_ac18_docstring_mentions_resolve_plugin_root(self):
        # AC: docstring に「file path 入力時は _resolve_plugin_root で親 traversal して
        #     plugin_root を抽出、deps.yaml 不在時は skip envelope を返す」を明記
        # RED: 実装前は docstring に該当記述がない
        from twl.mcp_server.tools import twl_validate_deps_handler

        doc = twl_validate_deps_handler.__doc__ or ""
        assert "_resolve_plugin_root" in doc, (
            "docstring に _resolve_plugin_root が記述されていない (AC18 未実装)"
        )
        assert "skip" in doc.lower(), (
            "docstring に skip に関する記述がない (AC18 未実装)"
        )


# ---------------------------------------------------------------------------
# AC19: _load_plugin_ctx は変更しない（シグネチャ確認）
# ---------------------------------------------------------------------------

class TestAC19LoadPluginCtxNotModified:
    """AC19: _load_plugin_ctx は変更しない."""

    def test_ac19_load_plugin_ctx_signature_unchanged(self):
        # AC: _load_plugin_ctx の signature は (plugin_root: str) → tuple[Path, dict, dict, str]
        # RED: 実装者が誤って変更した場合に FAIL（現状 PASS で問題なし、non-regression として維持）
        from twl.mcp_server.tools import _load_plugin_ctx

        sig = inspect.signature(_load_plugin_ctx)
        params = list(sig.parameters.keys())
        assert params == ["plugin_root"], (
            f"_load_plugin_ctx のシグネチャが変更されている (AC19 破壊): params={params}"
        )

    def test_ac19_load_plugin_ctx_source_unchanged(self):
        # AC: _load_plugin_ctx の実装に _resolve_plugin_root への参照がないこと
        #     (抽出ロジックは handler 側に閉じ込める)
        # RED: 実装者が誤って _load_plugin_ctx を修正した場合
        tools_src = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
        content = tools_src.read_text(encoding="utf-8")

        # _load_plugin_ctx の定義部分を抽出して _resolve_plugin_root が含まれないことを確認
        # （tools.py 全体には _resolve_plugin_root が含まれるため、関数内限定で検査）
        import ast
        tree = ast.parse(content)
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if node.name == "_load_plugin_ctx":
                    func_src = ast.get_source_segment(content, node) or ""
                    assert "_resolve_plugin_root" not in func_src, (
                        "_load_plugin_ctx 内に _resolve_plugin_root への参照が追加されている (AC19 破壊)"
                    )
                    break
