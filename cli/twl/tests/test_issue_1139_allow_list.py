"""Tests for Issue #1139: tech-debt: tools_comm.py _is_known_receiver hardcoded allow-list.

TDD RED フェーズ用テストスタブ。
対象実装ファイル: cli/twl/src/twl/mcp_server/tools_comm.py

AC 一覧:
  AC-1: _is_known_receiver() の prefix allow-list が module-level 単一変数として定義され、
        1 箇所のみの変更で新 receiver prefix 追加が可能なこと
  AC-2: _SUPERVISOR_NAME = "supervisor" 定数および exact-match 経路は本 Issue では変更しない
  AC-3: 既存呼び出し元について、pilot:/worker:/sibling:/supervisor は受理、不正値は拒否
  AC-4: 既存テスト (test_issue_1115_comm_tools.py) が全件 pass (テスト生成不要)
  AC-5: 新規回帰テスト — positive case (既存 prefix 受理) + negative case (unknown prefix 拒否)
  AC-6: 「新 prefix を追加する手順」を tools_comm.py docstring または _KNOWN_PREFIXES
        直前コメントに 1〜3 行で記述すること

RED の根拠:
  AC-1: 現在 _KNOWN_PREFIXES は tuple (immutable)。テストは list か regex であることを assert → FAIL
  AC-2: _SUPERVISOR_NAME 定数は存在するが、定数の型アノテーション (str) の有無を追加検証 → FAIL
  AC-3: 現在の実装で受理・拒否は正しく動作するが、
        リファクタリング後に _KNOWN_PREFIXES が mutable list / regex に変わっても
        振る舞いが不変なことを確認するテスト (現在は PASS、実装変更後に維持確認)
  AC-5(a): 同上 (positive case は現在 PASS)
  AC-5(b): unknown: prefix は現在 unknown_receiver を返す (現在 PASS)
  AC-6: 現在 docstring / _KNOWN_PREFIXES 直前コメントに「追加」「add」の記述がない → FAIL
"""

from __future__ import annotations

import importlib
import inspect
import json
import re
import tempfile
from pathlib import Path

import pytest

# ターゲットモジュールのパス
TOOLS_COMM_PATH = (
    Path(__file__).resolve().parent.parent
    / "src" / "twl" / "mcp_server" / "tools_comm.py"
)


# ---------------------------------------------------------------------------
# AC-1: _is_known_receiver() の prefix allow-list が module-level 単一変数
# ---------------------------------------------------------------------------


class TestAC1AllowListModuleLevelVariable:
    """AC-1: prefix allow-list が module-level 単一変数として定義されていること.

    現在 _KNOWN_PREFIXES は tuple (immutable)。
    実装後は list (mutable) または re.Pattern (_RECEIVER_PATTERN) として
    一箇所に集約されていることを assert する。
    現在の実装 (tuple) では FAIL する → RED。
    """

    def test_ac1_known_prefixes_is_mutable_list_or_regex_pattern(self):
        # AC: _KNOWN_PREFIXES が list (mutable) または re.Pattern (_RECEIVER_PATTERN) であること
        # RED: 現在 _KNOWN_PREFIXES は tuple (immutable) のため FAIL する
        from twl.mcp_server import tools_comm

        # _KNOWN_PREFIXES が list であるか、_RECEIVER_PATTERN (regex) が存在すること
        has_list_prefixes = hasattr(tools_comm, "_KNOWN_PREFIXES") and isinstance(
            tools_comm._KNOWN_PREFIXES, list
        )
        has_pattern = hasattr(tools_comm, "_RECEIVER_PATTERN") and isinstance(
            tools_comm._RECEIVER_PATTERN, re.Pattern
        )

        assert has_list_prefixes or has_pattern, (
            f"_KNOWN_PREFIXES が list でなく (type={type(getattr(tools_comm, '_KNOWN_PREFIXES', None)).__name__!r})、"
            f"かつ _RECEIVER_PATTERN も存在しない。"
            f"新 receiver prefix 追加が 1 箇所の変更で済む構造になっていない (AC-1 未実装)"
        )

    def test_ac1_module_level_allow_list_variable_exists(self):
        # AC: module-level に allow-list 変数が 1 つ存在すること
        # RED: 現在 _KNOWN_PREFIXES は tuple のため list/Pattern チェックで FAIL する
        from twl.mcp_server import tools_comm

        has_known_prefixes = hasattr(tools_comm, "_KNOWN_PREFIXES")
        has_receiver_pattern = hasattr(tools_comm, "_RECEIVER_PATTERN")

        assert has_known_prefixes or has_receiver_pattern, (
            "module に _KNOWN_PREFIXES も _RECEIVER_PATTERN も存在しない (AC-1 未実装)"
        )

        # 存在する場合は適切な型であることを確認
        if has_known_prefixes:
            prefixes = tools_comm._KNOWN_PREFIXES
            assert isinstance(prefixes, (list, re.Pattern)), (
                f"_KNOWN_PREFIXES の型が list/Pattern でない: {type(prefixes).__name__!r} (AC-1 未実装: tuple は不可)"
            )
        if has_receiver_pattern:
            pattern = tools_comm._RECEIVER_PATTERN
            assert isinstance(pattern, re.Pattern), (
                f"_RECEIVER_PATTERN が re.Pattern でない: {type(pattern).__name__!r} (AC-1 未実装)"
            )

    def test_ac1_adding_new_prefix_requires_only_one_place_change(self):
        # AC: _KNOWN_PREFIXES / _RECEIVER_PATTERN が mutable/拡張可能な構造であること
        # RED: 現在 tuple は append() を持たないため FAIL する
        from twl.mcp_server import tools_comm

        if hasattr(tools_comm, "_RECEIVER_PATTERN"):
            # regex pattern の場合は pattern 文字列が変更可能であることを確認 (静的確認のみ)
            assert isinstance(tools_comm._RECEIVER_PATTERN, re.Pattern), (
                "_RECEIVER_PATTERN が re.Pattern でない (AC-1 未実装)"
            )
        elif hasattr(tools_comm, "_KNOWN_PREFIXES"):
            prefixes = tools_comm._KNOWN_PREFIXES
            # mutable list であれば append() を持つ
            assert hasattr(prefixes, "append"), (
                f"_KNOWN_PREFIXES が mutable list でない (type={type(prefixes).__name__!r})。"
                f"新 prefix 追加が 1 箇所変更で済まない構造 (AC-1 未実装: tuple は immutable)"
            )
        else:
            pytest.fail("_KNOWN_PREFIXES も _RECEIVER_PATTERN も存在しない (AC-1 未実装)")


# ---------------------------------------------------------------------------
# AC-2: _SUPERVISOR_NAME 定数は変更しない
# ---------------------------------------------------------------------------


class TestAC2SupervisorNameConstantUnchanged:
    """AC-2: _SUPERVISOR_NAME = "supervisor" 定数および exact-match 経路は変更しない.

    この AC は「変更しないこと」の確認。定数の存在と値を assert する。
    現在の実装で _SUPERVISOR_NAME は存在し値も正しいが、
    型アノテーション (ClassVar[str] など) の有無も確認する。
    _SUPERVISOR_NAME が "supervisor" でない、または削除された場合に FAIL する。
    現在の実装では PASS するが、実装変更後の回帰防止テストとして機能する。

    注: 本 Issue のリファクタリング中に誤って _SUPERVISOR_NAME を変更した場合に RED になる。
    """

    def test_ac2_supervisor_name_constant_exists(self):
        # AC: _SUPERVISOR_NAME 定数が tools_comm モジュールに存在すること
        from twl.mcp_server import tools_comm

        assert hasattr(tools_comm, "_SUPERVISOR_NAME"), (
            "tools_comm に _SUPERVISOR_NAME 定数が存在しない (AC-2 未実装)"
        )

    def test_ac2_supervisor_name_value_is_supervisor(self):
        # AC: _SUPERVISOR_NAME の値が "supervisor" であること
        from twl.mcp_server import tools_comm

        assert tools_comm._SUPERVISOR_NAME == "supervisor", (
            f"_SUPERVISOR_NAME の値が 'supervisor' でない: {tools_comm._SUPERVISOR_NAME!r} (AC-2 違反)"
        )

    def test_ac2_supervisor_name_is_string_type(self):
        # AC: _SUPERVISOR_NAME が str 型であること
        from twl.mcp_server import tools_comm

        assert isinstance(tools_comm._SUPERVISOR_NAME, str), (
            f"_SUPERVISOR_NAME が str 型でない: {type(tools_comm._SUPERVISOR_NAME).__name__!r} (AC-2 違反)"
        )

    def test_ac2_twl_notify_supervisor_handler_uses_supervisor_name(self):
        # AC: twl_notify_supervisor_handler が _SUPERVISOR_NAME 定数を to= に使用していること
        # (ソースコード確認)
        # RED: リファクタリング中に to="supervisor" のハードコードに戻った場合に FAIL
        content = TOOLS_COMM_PATH.read_text()
        # _SUPERVISOR_NAME を使用していることを確認
        # twl_notify_supervisor_handler の実装内で _SUPERVISOR_NAME が参照されていること
        assert "_SUPERVISOR_NAME" in content, (
            "tools_comm.py に _SUPERVISOR_NAME 定数が定義されていない (AC-2 違反)"
        )
        # line 245 相当の to=_SUPERVISOR_NAME が存在すること
        assert "to=_SUPERVISOR_NAME" in content, (
            "twl_notify_supervisor_handler が to=_SUPERVISOR_NAME を使用していない (AC-2 違反: ハードコード禁止)"
        )


# ---------------------------------------------------------------------------
# AC-3: 後方互換 — 既存呼び出し元の挙動が不変であること
# ---------------------------------------------------------------------------


class TestAC3BackwardCompatibility:
    """AC-3: _send_msg_impl の後方互換性確認.

    pilot:foo / worker:bar / sibling:baz / supervisor は exit_code=0 で受理。
    不正値 (unknown prefix / invalid chars) は error_type + exit_code=3 を返す。
    リファクタリング後も振る舞いが不変であることを assert する。

    現在の実装では PASS するが、実装変更後の回帰防止テストとして機能する。
    """

    def test_ac3_pilot_prefix_accepted(self):
        # AC: "pilot:foo" が exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="pilot:foo", type_="t", content="c", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, (
                f"'pilot:foo' が受理されない (AC-3 違反): {result}"
            )
            assert result.get("exit_code") == 0, (
                f"'pilot:foo' の exit_code が 0 でない: {result.get('exit_code')} (AC-3 違反)"
            )

    def test_ac3_worker_prefix_accepted(self):
        # AC: "worker:bar" が exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="worker:bar", type_="t", content="c", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, (
                f"'worker:bar' が受理されない (AC-3 違反): {result}"
            )
            assert result.get("exit_code") == 0, (
                f"'worker:bar' の exit_code が 0 でない: {result.get('exit_code')} (AC-3 違反)"
            )

    def test_ac3_sibling_prefix_accepted(self):
        # AC: "sibling:baz" が exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="sibling:baz", type_="t", content="c", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, (
                f"'sibling:baz' が受理されない (AC-3 違反): {result}"
            )
            assert result.get("exit_code") == 0, (
                f"'sibling:baz' の exit_code が 0 でない: {result.get('exit_code')} (AC-3 違反)"
            )

    def test_ac3_supervisor_exact_match_accepted(self):
        # AC: "supervisor" が exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="supervisor", type_="t", content="c", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, (
                f"'supervisor' が受理されない (AC-3 違反): {result}"
            )
            assert result.get("exit_code") == 0, (
                f"'supervisor' の exit_code が 0 でない: {result.get('exit_code')} (AC-3 違反)"
            )

    def test_ac3_unknown_prefix_rejected_with_unknown_receiver(self):
        # AC: 不正な prefix (unknown:abc) が {"ok": false, "error_type": "unknown_receiver", "exit_code": 3} を返すこと
        from twl.mcp_server.tools_comm import twl_send_msg_handler
        result = json.loads(
            twl_send_msg_handler(to="unknown:abc", type_="t", content="c")
        )
        assert result.get("ok") is False, (
            f"'unknown:abc' が ok=False を返さない (AC-3 違反): {result}"
        )
        assert result.get("error_type") == "unknown_receiver", (
            f"'unknown:abc' の error_type が 'unknown_receiver' でない: {result.get('error_type')} (AC-3 違反)"
        )
        assert result.get("exit_code") == 3, (
            f"'unknown:abc' の exit_code が 3 でない: {result.get('exit_code')} (AC-3 違反)"
        )

    def test_ac3_invalid_chars_rejected_with_invalid_receiver(self):
        # AC: 不正文字 (../../etc/passwd) が {"ok": false, "error_type": "invalid_receiver", "exit_code": 3} を返すこと
        from twl.mcp_server.tools_comm import twl_send_msg_handler
        result = json.loads(
            twl_send_msg_handler(to="../../etc/passwd", type_="t", content="c")
        )
        assert result.get("ok") is False, (
            f"不正文字受信者で ok=False を返さない (AC-3 違反): {result}"
        )
        assert result.get("error_type") == "invalid_receiver", (
            f"不正文字の error_type が 'invalid_receiver' でない: {result.get('error_type')} (AC-3 違反)"
        )
        assert result.get("exit_code") == 3, (
            f"不正文字の exit_code が 3 でない: {result.get('exit_code')} (AC-3 違反)"
        )


# ---------------------------------------------------------------------------
# AC-5: 新規回帰テスト (option-agnostic)
# ---------------------------------------------------------------------------


class TestAC5RegressionTests:
    """AC-5: 新規回帰テスト.

    (a) 既存 prefix (pilot:foo / worker:bar / sibling:baz / supervisor) が
        すべて受理されることを assert する positive case
    (b) 想定外の prefix (unknown:abc) が error_type: "unknown_receiver" を返すことを
        assert する negative case

    実装方式 (regex / mutable list / register hook 等) に関わらず両 case が pass すること。
    """

    # --- (a) Positive cases: 既存 prefix はすべて受理 ---

    def test_ac5a_all_known_prefixes_accepted_in_batch(self):
        # AC: pilot:foo / worker:bar / sibling:baz / supervisor がすべて受理されること (batch)
        from twl.mcp_server.tools_comm import twl_send_msg_handler

        known_receivers = [
            "pilot:foo",
            "worker:bar",
            "sibling:baz",
            "supervisor",
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            for receiver in known_receivers:
                result = json.loads(
                    twl_send_msg_handler(
                        to=receiver, type_="test", content="ac5a", autopilot_dir=tmpdir
                    )
                )
                assert result.get("ok") is True, (
                    f"known receiver '{receiver}' が拒否された (AC-5(a) 違反): {result}"
                )
                assert result.get("exit_code") == 0, (
                    f"known receiver '{receiver}' の exit_code が 0 でない: {result.get('exit_code')} (AC-5(a) 違反)"
                )

    def test_ac5a_pilot_prefix_positive(self):
        # AC: "pilot:foo" が ok=True / exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="pilot:foo", type_="test", content="ok", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, f"pilot:foo が拒否された (AC-5(a) 違反): {result}"
            assert result.get("exit_code") == 0, f"pilot:foo exit_code != 0 (AC-5(a) 違反): {result}"

    def test_ac5a_worker_prefix_positive(self):
        # AC: "worker:bar" が ok=True / exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="worker:bar", type_="test", content="ok", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, f"worker:bar が拒否された (AC-5(a) 違反): {result}"
            assert result.get("exit_code") == 0, f"worker:bar exit_code != 0 (AC-5(a) 違反): {result}"

    def test_ac5a_sibling_prefix_positive(self):
        # AC: "sibling:baz" が ok=True / exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="sibling:baz", type_="test", content="ok", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, f"sibling:baz が拒否された (AC-5(a) 違反): {result}"
            assert result.get("exit_code") == 0, f"sibling:baz exit_code != 0 (AC-5(a) 違反): {result}"

    def test_ac5a_supervisor_positive(self):
        # AC: "supervisor" が ok=True / exit_code=0 で受理されること
        with tempfile.TemporaryDirectory() as tmpdir:
            from twl.mcp_server.tools_comm import twl_send_msg_handler
            result = json.loads(
                twl_send_msg_handler(to="supervisor", type_="test", content="ok", autopilot_dir=tmpdir)
            )
            assert result.get("ok") is True, f"supervisor が拒否された (AC-5(a) 違反): {result}"
            assert result.get("exit_code") == 0, f"supervisor exit_code != 0 (AC-5(a) 違反): {result}"

    # --- (b) Negative case: 想定外 prefix は unknown_receiver ---

    def test_ac5b_unknown_prefix_returns_unknown_receiver_error(self):
        # AC: "unknown:abc" が {"ok": false, "error_type": "unknown_receiver", "exit_code": 3} を返すこと
        from twl.mcp_server.tools_comm import twl_send_msg_handler
        result = json.loads(
            twl_send_msg_handler(to="unknown:abc", type_="test", content="bad")
        )
        assert result.get("ok") is False, (
            f"'unknown:abc' が ok=False を返さない (AC-5(b) 違反): {result}"
        )
        assert result.get("error_type") == "unknown_receiver", (
            f"'unknown:abc' の error_type が 'unknown_receiver' でない: {result.get('error_type')} (AC-5(b) 違反)"
        )
        assert result.get("exit_code") == 3, (
            f"'unknown:abc' の exit_code が 3 でない: {result.get('exit_code')} (AC-5(b) 違反)"
        )

    def test_ac5b_other_unknown_prefixes_also_rejected(self):
        # AC: 他の想定外 prefix も unknown_receiver を返すこと
        from twl.mcp_server.tools_comm import twl_send_msg_handler

        unknown_receivers = [
            "manager:foo",
            "agent:bar",
            "bot:baz",
            "supervisor2",  # "supervisor" の exact-match ではない
        ]
        for receiver in unknown_receivers:
            result = json.loads(
                twl_send_msg_handler(to=receiver, type_="test", content="bad")
            )
            assert result.get("ok") is False, (
                f"unknown receiver '{receiver}' が ok=False を返さない (AC-5(b) 違反): {result}"
            )
            assert result.get("error_type") == "unknown_receiver", (
                f"'{receiver}' の error_type が 'unknown_receiver' でない: {result.get('error_type')} (AC-5(b) 違反)"
            )


# ---------------------------------------------------------------------------
# AC-6: 拡張方法ドキュメント
# ---------------------------------------------------------------------------


class TestAC6ExtensionDocumentation:
    """AC-6: 「新 prefix を追加する手順」が docstring または _KNOWN_PREFIXES 直前コメントに記述されること.

    現在 tools_comm.py の docstring には「追加」「add」の記述がなく、
    _KNOWN_PREFIXES 直前にもコメントがない → RED (FAIL)。
    """

    def test_ac6_docstring_or_comment_contains_add_instruction(self):
        # AC: tools_comm.py の docstring または _KNOWN_PREFIXES 直前コメントに
        #     「追加」「add」の単語が含まれること
        # RED: 現在 docstring / コメントに追加方法の記述がないため FAIL する
        from twl.mcp_server import tools_comm

        content = TOOLS_COMM_PATH.read_text()
        module_doc = tools_comm.__doc__ or ""

        # docstring に「追加」「add」があるか確認
        doc_has_instruction = (
            "追加" in module_doc.lower() or "add" in module_doc.lower()
        )

        # _KNOWN_PREFIXES 直前 3 行にコメントがあるか確認
        lines = content.split("\n")
        prefix_line_idx = None
        for i, line in enumerate(lines):
            if "_KNOWN_PREFIXES" in line and "=" in line and "def" not in line and i < 50:
                prefix_line_idx = i
                break

        comment_has_instruction = False
        if prefix_line_idx is not None:
            preceding_lines = lines[max(0, prefix_line_idx - 3) : prefix_line_idx]
            preceding_text = " ".join(preceding_lines).lower()
            comment_has_instruction = "追加" in preceding_text or "add" in preceding_text

        assert doc_has_instruction or comment_has_instruction, (
            "tools_comm.py の docstring および _KNOWN_PREFIXES 直前コメントに "
            "新 prefix 追加手順 ('追加' または 'add' の単語) が含まれない (AC-6 未実装)"
        )

    def test_ac6_docstring_or_comment_has_how_to_add_prefix(self):
        # AC: 「新 prefix を追加する手順」が docstring または _KNOWN_PREFIXES 前後に記述されていること
        # RED: 現在記述がないため FAIL する
        content = TOOLS_COMM_PATH.read_text()

        # "追加" または "add" を含む行が _KNOWN_PREFIXES 定義の近く (前後 5 行) にあるか、
        # またはモジュール docstring に含まれるか
        lines = content.split("\n")

        # モジュール docstring の確認 (ファイル先頭の """...""")
        doc_end_idx = None
        if lines[0].startswith('"""') or lines[0].startswith("'''"):
            for i, line in enumerate(lines[1:], 1):
                if '"""' in line or "'''" in line:
                    doc_end_idx = i
                    break
        docstring_lines = lines[: doc_end_idx + 1] if doc_end_idx else []
        docstring_text = " ".join(docstring_lines).lower()
        doc_has = "追加" in docstring_text or "add" in docstring_text

        # _KNOWN_PREFIXES 周辺のコメント確認
        prefix_idx = None
        for i, line in enumerate(lines):
            if "_KNOWN_PREFIXES" in line and "=" in line and "def" not in line and i < 50:
                prefix_idx = i
                break

        context_has = False
        if prefix_idx is not None:
            context_lines = lines[max(0, prefix_idx - 5) : prefix_idx + 3]
            context_text = " ".join(context_lines).lower()
            context_has = "追加" in context_text or "add" in context_text

        assert doc_has or context_has, (
            "tools_comm.py の docstring または _KNOWN_PREFIXES 前後に "
            "新 prefix 追加手順の記述 ('追加'/'add') がない (AC-6 未実装)"
        )

    def test_ac6_extension_comment_is_1_to_3_lines(self):
        # AC: 追加手順コメントが 1〜3 行で記述されていること (簡潔であること)
        # RED: 現在コメントが存在しないため FAIL する (コメントが 0 行)
        content = TOOLS_COMM_PATH.read_text()
        lines = content.split("\n")

        # _KNOWN_PREFIXES 直前のコメント行を収集
        prefix_idx = None
        for i, line in enumerate(lines):
            if "_KNOWN_PREFIXES" in line and "=" in line and "def" not in line and i < 50:
                prefix_idx = i
                break

        if prefix_idx is None:
            # _KNOWN_PREFIXES が見つからない場合は _RECEIVER_PATTERN を確認
            for i, line in enumerate(lines):
                if "_RECEIVER_PATTERN" in line and "=" in line and i < 50:
                    prefix_idx = i
                    break

        assert prefix_idx is not None, (
            "tools_comm.py に _KNOWN_PREFIXES も _RECEIVER_PATTERN も見つからない (AC-1/AC-6 未実装)"
        )

        # 直前のコメント行を収集 (# で始まる行)
        comment_lines = []
        for i in range(prefix_idx - 1, max(prefix_idx - 6, -1), -1):
            if lines[i].strip().startswith("#"):
                comment_lines.append(lines[i])
            elif lines[i].strip() == "":
                continue
            else:
                break

        # コメントが存在し (1 行以上)、多すぎない (3 行以下) こと
        assert len(comment_lines) >= 1, (
            f"_KNOWN_PREFIXES 直前に追加手順コメントが存在しない (AC-6 未実装): "
            f"コメント行数={len(comment_lines)}"
        )
        assert len(comment_lines) <= 3, (
            f"追加手順コメントが 3 行を超えている: {len(comment_lines)} 行 (AC-6: 1〜3 行で記述)"
        )
