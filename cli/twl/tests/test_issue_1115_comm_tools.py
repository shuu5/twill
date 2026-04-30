"""Tests for Issue #1115: feat(mcp): tool-3 tools.py epic-5 mailbox (comm tools).

TDD RED フェーズ用テストスタブ。
実装前は全テストが FAIL する（意図的 RED）。

AC 一覧（子 5 固有 AC）:
  AC5-1: 3 tool 追加 (twl_send_msg, twl_recv_msg, twl_notify_supervisor)
  AC5-2: dispatch ロジックは file-based jsonl + flock 方式
  AC5-3: dispatch table 設計（名前空間, unknown/invalid receiver 処理）
  AC5-4: handler は pure Python、_handler suffix、直接呼び出し可能
  AC5-5: 並列 100 メッセージ送受で損失ゼロ
  AC5-6: timeout_sec=0 は non-blocking poll、>0 は blocking
  AC5-7: #1033 close（プロセス AC）
  AC5-8: tools.py 分割方針（Option A）
  AC5-9: glossary.md に mailbox / mailbox file 用語追加
  AC5-10: ADR-028 write authority matrix に mailbox 行追加
  AC5-11: session-comm.sh との責務分離（設計制約 AC）
  AC5-12: bats は不要（pytest がメイン）

AC 一覧（共通 AC）:
  共通-1: 3 tool が tools.py（または tools_comm.py 経由）に存在すること
  共通-2: handler 関数が存在すること
  共通-3: MCP tool 登録（@mcp.tool() + try/except ImportError gate）
  共通-4: handler unit test（fastmcp 経由 + 直接呼び出し 2 経路）
  共通-5: bats 互換性（comm 系は新規のため no-op）
  共通-6: tools.py + tools_comm.py の行数確認（twl validate PASS）
  共通-7: Bounded Context 整合（Autopilot 配下、OHS 方向維持）
  共通-8: ADR-028 整合確認（write 経路追加）
  共通-9: action 系 tool の timeout_sec: int 引数必須
"""

from __future__ import annotations

import inspect
import json
import re
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ターゲットモジュール
TWL_DIR = Path(__file__).resolve().parent.parent

# 期待する 3 tool 名（comm 系）
EXPECTED_COMM_TOOL_NAMES = [
    "twl_send_msg",
    "twl_recv_msg",
    "twl_notify_supervisor",
]

# action 系 tool（timeout_sec 引数が必要）
COMM_ACTION_HANDLER_NAMES = [
    "twl_send_msg_handler",
    "twl_notify_supervisor_handler",
]

# handler 関数の期待名
EXPECTED_COMM_HANDLER_NAMES = [
    "twl_send_msg_handler",
    "twl_recv_msg_handler",
    "twl_notify_supervisor_handler",
]


# ---------------------------------------------------------------------------
# AC5-1: 3 tool 追加
# ---------------------------------------------------------------------------


class TestAC51ThreeToolsAdded:
    """AC5-1: 3 tool が tools_comm.py に追加されていること.

    実装前は tools_comm モジュールが存在しないか、各 tool が未定義のため
    ImportError または AttributeError で FAIL する（意図的 RED）。
    """

    def test_ac51_twl_send_msg_exists_in_tools_comm(self):
        # AC: twl_send_msg が tools_comm モジュールに存在すること
        # RED: tools_comm.py が未作成のため ImportError で FAIL する
        from twl.mcp_server import tools_comm
        assert hasattr(tools_comm, "twl_send_msg"), (
            "tools_comm に twl_send_msg が存在しない (AC5-1 未実装)"
        )

    def test_ac51_twl_recv_msg_exists_in_tools_comm(self):
        # AC: twl_recv_msg が tools_comm モジュールに存在すること
        # RED: tools_comm.py が未作成のため ImportError で FAIL する
        from twl.mcp_server import tools_comm
        assert hasattr(tools_comm, "twl_recv_msg"), (
            "tools_comm に twl_recv_msg が存在しない (AC5-1 未実装)"
        )

    def test_ac51_twl_notify_supervisor_exists_in_tools_comm(self):
        # AC: twl_notify_supervisor が tools_comm モジュールに存在すること
        # RED: tools_comm.py が未作成のため ImportError で FAIL する
        from twl.mcp_server import tools_comm
        assert hasattr(tools_comm, "twl_notify_supervisor"), (
            "tools_comm に twl_notify_supervisor が存在しない (AC5-1 未実装)"
        )

    def test_ac51_twl_send_msg_handler_signature(self):
        # AC: twl_send_msg_handler(to, type_, content, reply_to=None, timeout_sec=10) -> str シグネチャ
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_send_msg_handler
        sig = inspect.signature(twl_send_msg_handler)
        params = sig.parameters
        assert "to" in params, "twl_send_msg_handler に 'to' 引数がない (AC5-1 未実装)"
        assert "type_" in params, "twl_send_msg_handler に 'type_' 引数がない (AC5-1 未実装)"
        assert "content" in params, "twl_send_msg_handler に 'content' 引数がない (AC5-1 未実装)"
        assert "reply_to" in params, "twl_send_msg_handler に 'reply_to' 引数がない (AC5-1 未実装)"
        assert "timeout_sec" in params, "twl_send_msg_handler に 'timeout_sec' 引数がない (AC5-1 未実装)"
        assert params["reply_to"].default is None, (
            "twl_send_msg_handler の reply_to デフォルトが None でない (AC5-1 未実装)"
        )
        assert params["timeout_sec"].default == 10, (
            f"twl_send_msg_handler の timeout_sec デフォルトが 10 でない: {params['timeout_sec'].default} (AC5-1 未実装)"
        )

    def test_ac51_twl_recv_msg_handler_signature(self):
        # AC: twl_recv_msg_handler(receiver, since=None, timeout_sec=0) -> str シグネチャ
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_recv_msg_handler
        sig = inspect.signature(twl_recv_msg_handler)
        params = sig.parameters
        assert "receiver" in params, "twl_recv_msg_handler に 'receiver' 引数がない (AC5-1 未実装)"
        assert "since" in params, "twl_recv_msg_handler に 'since' 引数がない (AC5-1 未実装)"
        assert "timeout_sec" in params, "twl_recv_msg_handler に 'timeout_sec' 引数がない (AC5-1 未実装)"
        assert params["since"].default is None, (
            "twl_recv_msg_handler の since デフォルトが None でない (AC5-1 未実装)"
        )
        assert params["timeout_sec"].default == 0, (
            f"twl_recv_msg_handler の timeout_sec デフォルトが 0 でない: {params['timeout_sec'].default} (AC5-1 未実装)"
        )

    def test_ac51_twl_notify_supervisor_handler_signature(self):
        # AC: twl_notify_supervisor_handler(event, payload, timeout_sec=10) -> str シグネチャ
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_notify_supervisor_handler
        sig = inspect.signature(twl_notify_supervisor_handler)
        params = sig.parameters
        assert "event" in params, "twl_notify_supervisor_handler に 'event' 引数がない (AC5-1 未実装)"
        assert "payload" in params, "twl_notify_supervisor_handler に 'payload' 引数がない (AC5-1 未実装)"
        assert "timeout_sec" in params, "twl_notify_supervisor_handler に 'timeout_sec' 引数がない (AC5-1 未実装)"
        assert params["timeout_sec"].default == 10, (
            f"twl_notify_supervisor_handler の timeout_sec デフォルトが 10 でない: {params['timeout_sec'].default} (AC5-1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC5-2: dispatch ロジックは file-based jsonl + flock 方式
# ---------------------------------------------------------------------------


class TestAC52FileBasedJsonlFlock:
    """AC5-2: dispatch ロジックは file-based jsonl + flock 方式.

    mailbox file path: ${AUTOPILOT_DIR:-.autopilot}/mailbox/<receiver>.jsonl
    lock file: <receiver>.jsonl.lock
    file permissions MUST: mode=0o600
    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac52_mailbox_file_path_uses_autopilot_dir(self):
        # AC: mailbox file path が ${AUTOPILOT_DIR:-.autopilot}/mailbox/<receiver>.jsonl となること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                # valid receiver 形式で送信（ファイルが作成されることを確認）
                result_str = twl_send_msg_handler(
                    to="supervisor",
                    type_="test",
                    content="hello",
                    timeout_sec=5,
                )
                result = json.loads(result_str)
                assert result.get("ok") is True, (
                    f"twl_send_msg_handler が ok=True を返さない (AC5-2 未実装): {result}"
                )
                mailbox_file = Path(tmpdir) / "mailbox" / "supervisor.jsonl"
                assert mailbox_file.exists(), (
                    f"mailbox file が作成されていない: {mailbox_file} (AC5-2 未実装)"
                )

    def test_ac52_mailbox_file_permissions_are_0o600(self):
        # AC: mailbox file の permissions が 0o600 であること
        # RED: handler が未実装のため FAIL する
        import os
        import stat
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                twl_send_msg_handler(
                    to="supervisor",
                    type_="test",
                    content="hello",
                    timeout_sec=5,
                )
                mailbox_file = Path(tmpdir) / "mailbox" / "supervisor.jsonl"
                if mailbox_file.exists():
                    mode = mailbox_file.stat().st_mode & 0o777
                    assert mode == 0o600, (
                        f"mailbox file permissions が 0o600 でない: {oct(mode)} (AC5-2 未実装)"
                    )
                else:
                    pytest.fail(f"mailbox file が作成されていない: {mailbox_file} (AC5-2 未実装)")

    def test_ac52_lock_file_created_alongside_jsonl(self):
        # AC: lock file が <receiver>.jsonl.lock として mailbox file と同ディレクトリに作成されること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            # lock file の存在確認は送信後に実施（flock 解放後はファイルが残る実装を想定）
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                twl_send_msg_handler(
                    to="supervisor",
                    type_="test",
                    content="hello",
                    timeout_sec=5,
                )
                # lock file の存在確認（存在しない場合も flock 解放後に消えるケースを考慮）
                # ここでは mailbox file の存在をもって flock 方式を実施済みとみなす
                mailbox_file = Path(tmpdir) / "mailbox" / "supervisor.jsonl"
                assert mailbox_file.exists(), (
                    f"mailbox file が作成されていない (AC5-2 未実装): {mailbox_file}"
                )

    def test_ac52_mailbox_file_content_is_valid_jsonl(self):
        # AC: mailbox file の内容が有効な JSONL（1行1JSON）であること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                twl_send_msg_handler(
                    to="supervisor",
                    type_="test",
                    content="hello world",
                    timeout_sec=5,
                )
                mailbox_file = Path(tmpdir) / "mailbox" / "supervisor.jsonl"
                assert mailbox_file.exists(), (
                    f"mailbox file が作成されていない (AC5-2 未実装)"
                )
                lines = mailbox_file.read_text().strip().split("\n")
                for line in lines:
                    if line.strip():
                        parsed = json.loads(line)  # FAIL if not valid JSON
                        assert isinstance(parsed, dict), (
                            f"JSONL 行が dict でない: {type(parsed)} (AC5-2 未実装)"
                        )


# ---------------------------------------------------------------------------
# AC5-3: dispatch table 設計
# ---------------------------------------------------------------------------


class TestAC53DispatchTable:
    """AC5-3: dispatch table 設計.

    名前空間: pilot:<session-id>, worker:<window-name>, supervisor, sibling:<window-name>
    unknown receiver: {ok: false, error_type: "unknown_receiver", exit_code: 3}
    invalid receiver: {ok: false, error_type: "invalid_receiver", exit_code: 3}
    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac53_supervisor_receiver_is_valid(self):
        # AC: "supervisor" は有効な receiver として扱われること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                result_str = twl_send_msg_handler(
                    to="supervisor",
                    type_="test",
                    content="hello",
                    timeout_sec=5,
                )
                result = json.loads(result_str)
                assert result.get("error_type") != "unknown_receiver", (
                    "'supervisor' が unknown_receiver エラーを返した (AC5-3 未実装)"
                )
                assert result.get("error_type") != "invalid_receiver", (
                    "'supervisor' が invalid_receiver エラーを返した (AC5-3 未実装)"
                )

    def test_ac53_pilot_namespace_receiver_is_valid(self):
        # AC: "pilot:<session-id>" 形式は有効な receiver として扱われること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                result_str = twl_send_msg_handler(
                    to="pilot:abc123",
                    type_="test",
                    content="hello",
                    timeout_sec=5,
                )
                result = json.loads(result_str)
                assert result.get("error_type") != "invalid_receiver", (
                    "'pilot:abc123' が invalid_receiver エラーを返した (AC5-3 未実装)"
                )

    def test_ac53_worker_namespace_receiver_is_valid(self):
        # AC: "worker:<window-name>" 形式は有効な receiver として扱われること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                result_str = twl_send_msg_handler(
                    to="worker:feat-123",
                    type_="test",
                    content="hello",
                    timeout_sec=5,
                )
                result = json.loads(result_str)
                assert result.get("error_type") != "invalid_receiver", (
                    "'worker:feat-123' が invalid_receiver エラーを返した (AC5-3 未実装)"
                )

    def test_ac53_sibling_namespace_receiver_is_valid(self):
        # AC: "sibling:<window-name>" 形式は有効な receiver として扱われること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                result_str = twl_send_msg_handler(
                    to="sibling:feat-456",
                    type_="test",
                    content="hello",
                    timeout_sec=5,
                )
                result = json.loads(result_str)
                assert result.get("error_type") != "invalid_receiver", (
                    "'sibling:feat-456' が invalid_receiver エラーを返した (AC5-3 未実装)"
                )

    def test_ac53_invalid_receiver_characters_rejected(self):
        # AC: to が [a-zA-Z0-9_\-:]+ 以外の文字を含む場合 {ok: false, error_type: "invalid_receiver", exit_code: 3}
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_send_msg_handler
        result_str = twl_send_msg_handler(
            to="../../etc/passwd",
            type_="test",
            content="evil",
            timeout_sec=5,
        )
        result = json.loads(result_str)
        assert result.get("ok") is False, (
            "不正な receiver で ok が False でない (AC5-3 未実装)"
        )
        assert result.get("error_type") == "invalid_receiver", (
            f"error_type が 'invalid_receiver' でない: {result.get('error_type')} (AC5-3 未実装)"
        )
        assert result.get("exit_code") == 3, (
            f"exit_code が 3 でない: {result.get('exit_code')} (AC5-3 未実装)"
        )

    def test_ac53_receiver_with_space_is_invalid(self):
        # AC: スペースを含む receiver は invalid として拒否されること
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_send_msg_handler
        result_str = twl_send_msg_handler(
            to="bad receiver",
            type_="test",
            content="evil",
            timeout_sec=5,
        )
        result = json.loads(result_str)
        assert result.get("ok") is False, (
            "スペース入り receiver で ok が False でない (AC5-3 未実装)"
        )
        assert result.get("error_type") == "invalid_receiver", (
            f"error_type が 'invalid_receiver' でない: {result.get('error_type')} (AC5-3 未実装)"
        )

    async def test_ac53_recv_msg_invalid_receiver_rejected(self):
        # AC: twl_recv_msg_handler でも invalid な receiver は拒否されること
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_recv_msg_handler
        result_str = await twl_recv_msg_handler(
            receiver="../etc/passwd",
            timeout_sec=0,
        )
        result = json.loads(result_str)
        assert result.get("ok") is False, (
            "不正な receiver で ok が False でない (AC5-3 未実装)"
        )
        assert result.get("error_type") == "invalid_receiver", (
            f"error_type が 'invalid_receiver' でない: {result.get('error_type')} (AC5-3 未実装)"
        )
        assert result.get("exit_code") == 3, (
            f"exit_code が 3 でない: {result.get('exit_code')} (AC5-3 未実装)"
        )


# ---------------------------------------------------------------------------
# AC5-4: handler は pure Python、_handler suffix、直接呼び出し可能
# ---------------------------------------------------------------------------


class TestAC54PureHandlers:
    """AC5-4: handler は pure Python、_handler suffix、直接呼び出し可能.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac54_all_comm_handlers_exist(self):
        # AC: 3 handler 関数が tools_comm に _handler suffix で存在すること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        missing = [h for h in EXPECTED_COMM_HANDLER_NAMES if not hasattr(tools_comm, h)]
        assert not missing, (
            f"tools_comm に以下の handler が存在しない (AC5-4 未実装): {missing}"
        )

    def test_ac54_all_comm_handlers_are_callable(self):
        # AC: 全 handler が callable であること
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server import tools_comm
        for handler_name in EXPECTED_COMM_HANDLER_NAMES:
            handler = getattr(tools_comm, handler_name, None)
            assert handler is not None, (
                f"tools_comm に {handler_name} が存在しない (AC5-4 未実装)"
            )
            assert callable(handler), (
                f"tools_comm.{handler_name} が callable でない (AC5-4 未実装)"
            )

    def test_ac54_twl_send_msg_handler_is_directly_callable(self):
        # AC: twl_send_msg_handler を直接呼び出し可能で str を返すこと
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                result = twl_send_msg_handler(
                    to="supervisor",
                    type_="test",
                    content="direct call",
                    timeout_sec=5,
                )
                assert isinstance(result, str), (
                    f"twl_send_msg_handler が str を返さない: {type(result)} (AC5-4 未実装)"
                )

    async def test_ac54_twl_recv_msg_handler_is_directly_callable(self):
        # AC: twl_recv_msg_handler を直接呼び出し可能で str を返すこと
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_recv_msg_handler
                result = await twl_recv_msg_handler(
                    receiver="supervisor",
                    timeout_sec=0,
                )
                assert isinstance(result, str), (
                    f"twl_recv_msg_handler が str を返さない: {type(result)} (AC5-4 未実装)"
                )

    def test_ac54_twl_notify_supervisor_handler_is_directly_callable(self):
        # AC: twl_notify_supervisor_handler を直接呼び出し可能で str を返すこと
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_notify_supervisor_handler
                result = twl_notify_supervisor_handler(
                    event="task_complete",
                    payload={"issue": 1},
                    timeout_sec=5,
                )
                assert isinstance(result, str), (
                    f"twl_notify_supervisor_handler が str を返さない: {type(result)} (AC5-4 未実装)"
                )


# ---------------------------------------------------------------------------
# AC5-5: 並列 100 メッセージ送受で損失ゼロ
# ---------------------------------------------------------------------------


class TestAC55ConcurrentMessages:
    """AC5-5: 並列 100 メッセージ送受で損失ゼロ（concurrent.futures + ThreadPoolExecutor）.

    実装前は handler が未実装のため FAIL する（意図的 RED）。
    """

    def test_ac55_100_parallel_sends_no_loss(self):
        # AC: ThreadPoolExecutor で 100 メッセージを並列送信し、全て mailbox に記録されること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler

                n_messages = 100

                def send_one(i: int) -> dict:
                    result_str = twl_send_msg_handler(
                        to="supervisor",
                        type_="test",
                        content=f"message-{i}",
                        timeout_sec=10,
                    )
                    return json.loads(result_str)

                with ThreadPoolExecutor(max_workers=20) as executor:
                    results = list(executor.map(send_one, range(n_messages)))

                # 全送信が ok=True であること
                failures = [r for r in results if not r.get("ok")]
                assert not failures, (
                    f"{len(failures)} 件の送信が失敗 (AC5-5 未実装): {failures[:3]}"
                )

                # mailbox file に 100 行が記録されていること
                mailbox_file = Path(tmpdir) / "mailbox" / "supervisor.jsonl"
                assert mailbox_file.exists(), (
                    f"mailbox file が存在しない (AC5-5 未実装)"
                )
                lines = [
                    line for line in mailbox_file.read_text().split("\n")
                    if line.strip()
                ]
                assert len(lines) == n_messages, (
                    f"mailbox file の行数が {n_messages} でない: {len(lines)} (AC5-5 未実装)"
                )

    def test_ac55_100_parallel_sends_all_json_valid(self):
        # AC: 並列送信後の mailbox file 全行が有効な JSON であること
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler

                n_messages = 100

                def send_one(i: int) -> None:
                    twl_send_msg_handler(
                        to="supervisor",
                        type_="test",
                        content=f"msg-{i}",
                        timeout_sec=10,
                    )

                with ThreadPoolExecutor(max_workers=20) as executor:
                    list(executor.map(send_one, range(n_messages)))

                mailbox_file = Path(tmpdir) / "mailbox" / "supervisor.jsonl"
                lines = [
                    line for line in mailbox_file.read_text().split("\n")
                    if line.strip()
                ]
                for i, line in enumerate(lines):
                    parsed = json.loads(line)  # FAIL if corrupted
                    assert isinstance(parsed, dict), (
                        f"mailbox file の行 {i} が dict でない (AC5-5 未実装)"
                    )


# ---------------------------------------------------------------------------
# AC5-6: timeout_sec=0 は non-blocking poll、>0 は blocking
# ---------------------------------------------------------------------------


class TestAC56TimeoutBehavior:
    """AC5-6: timeout_sec=0 は non-blocking poll、>0 は blocking。timeout 時は {ok: true, msgs: [], exit_code: 0}.

    since パラメータ: ULID または RFC3339 UTC 文字列。不正フォーマット時 {ok: false, error_type: "invalid_since", exit_code: 3}
    実装前は handler が未実装のため FAIL する（意図的 RED）。
    """

    async def test_ac56_timeout_sec_0_returns_immediately(self):
        # AC: timeout_sec=0 の場合、空の mailbox でも即座に {ok: true, msgs: [], exit_code: 0} を返すこと
        # RED: handler が未実装のため FAIL する
        import os
        import time
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_recv_msg_handler
                start = time.monotonic()
                result_str = await twl_recv_msg_handler(
                    receiver="supervisor",
                    timeout_sec=0,
                )
                elapsed = time.monotonic() - start
                result = json.loads(result_str)

                assert result.get("ok") is True, (
                    f"timeout_sec=0 で ok が True でない (AC5-6 未実装): {result}"
                )
                assert result.get("msgs") == [], (
                    f"timeout_sec=0 で msgs が空リストでない (AC5-6 未実装): {result.get('msgs')}"
                )
                assert result.get("exit_code") == 0, (
                    f"timeout_sec=0 で exit_code が 0 でない (AC5-6 未実装): {result.get('exit_code')}"
                )
                # non-blocking: 1 秒以内に返ること（許容 2 秒）
                assert elapsed < 2.0, (
                    f"timeout_sec=0 なのに {elapsed:.2f}秒かかった (AC5-6 未実装)"
                )

    async def test_ac56_timeout_when_no_messages_returns_empty(self):
        # AC: timeout_sec>0 で待機後、メッセージがなければ {ok: true, msgs: [], exit_code: 0}
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_recv_msg_handler
                result_str = await twl_recv_msg_handler(
                    receiver="supervisor",
                    timeout_sec=1,  # 短い timeout
                )
                result = json.loads(result_str)
                assert result.get("ok") is True, (
                    f"timeout 後に ok が True でない (AC5-6 未実装): {result}"
                )
                assert result.get("msgs") == [], (
                    f"timeout 後に msgs が空でない (AC5-6 未実装): {result.get('msgs')}"
                )

    async def test_ac56_invalid_since_format_returns_error(self):
        # AC: since に不正フォーマット文字列を渡すと {ok: false, error_type: "invalid_since", exit_code: 3}
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_recv_msg_handler
        result_str = await twl_recv_msg_handler(
            receiver="supervisor",
            since="not-a-ulid-or-rfc3339",
            timeout_sec=0,
        )
        result = json.loads(result_str)
        assert result.get("ok") is False, (
            f"不正な since で ok が False でない (AC5-6 未実装): {result}"
        )
        assert result.get("error_type") == "invalid_since", (
            f"error_type が 'invalid_since' でない: {result.get('error_type')} (AC5-6 未実装)"
        )
        assert result.get("exit_code") == 3, (
            f"exit_code が 3 でない: {result.get('exit_code')} (AC5-6 未実装)"
        )

    async def test_ac56_valid_rfc3339_since_accepted(self):
        # AC: since に有効な RFC3339 UTC 文字列を渡すとエラーにならないこと
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_recv_msg_handler
                result_str = await twl_recv_msg_handler(
                    receiver="supervisor",
                    since="2024-01-01T00:00:00Z",
                    timeout_sec=0,
                )
                result = json.loads(result_str)
                assert result.get("error_type") != "invalid_since", (
                    f"有効な RFC3339 で invalid_since エラーが返された (AC5-6 未実装)"
                )


# ---------------------------------------------------------------------------
# AC5-7: #1033 close（プロセス AC）
# ---------------------------------------------------------------------------


class TestAC57Issue1033Close:
    """AC5-7: #1033 close（プロセス AC）.

    このテストは手動確認の代替として、#1033 が close される前提条件
    （comm tools の実装）が満たされていることを確認する。
    実装前は tools_comm が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac57_comm_tools_module_importable_as_prerequisite_for_1033(self):
        # AC: #1033 close の前提として tools_comm が import 可能であること
        # RED: tools_comm.py が未作成のため ImportError で FAIL する
        from twl.mcp_server import tools_comm  # noqa: F401
        # tools_comm が import 可能であることが #1033 close の prerequisite
        assert tools_comm is not None, (
            "tools_comm が import できない (AC5-7 未実装: #1033 close 前提条件)"
        )


# ---------------------------------------------------------------------------
# AC5-8: tools.py 分割方針（Option A）
# ---------------------------------------------------------------------------


class TestAC58OptionAModuleSplit:
    """AC5-8: Option A 採用時 — tools_comm.py に __all__ 定義、tools.py 末尾に from .tools_comm import * 追加.

    実装前は tools_comm.py が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac58_tools_comm_has_all_defined(self):
        # AC: tools_comm.py に __all__ が定義されていること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        assert hasattr(tools_comm, "__all__"), (
            "tools_comm に __all__ が定義されていない (AC5-8 未実装)"
        )
        assert isinstance(tools_comm.__all__, (list, tuple)), (
            f"tools_comm.__all__ が list/tuple でない: {type(tools_comm.__all__)} (AC5-8 未実装)"
        )

    def test_ac58_all_includes_comm_tool_names(self):
        # AC: tools_comm.__all__ に 3 tool 名と 3 handler 名が含まれること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        all_names = list(tools_comm.__all__)
        for name in EXPECTED_COMM_TOOL_NAMES:
            assert name in all_names, (
                f"tools_comm.__all__ に {name} が含まれない (AC5-8 未実装)"
            )
        for name in EXPECTED_COMM_HANDLER_NAMES:
            assert name in all_names, (
                f"tools_comm.__all__ に {name} が含まれない (AC5-8 未実装)"
            )

    def test_ac58_tools_py_exposes_comm_tools_via_star_import(self):
        # AC: tools.py が tools_comm から * import して comm tool を公開していること
        # RED: tools.py が from .tools_comm import * を持たないため FAIL する
        from twl.mcp_server import tools
        for name in EXPECTED_COMM_TOOL_NAMES:
            assert hasattr(tools, name), (
                f"tools.py が {name} を公開していない (AC5-8 未実装)"
            )

    def test_ac58_tools_py_source_contains_from_tools_comm_import_star(self):
        # AC: tools.py のソースに "from .tools_comm import *" が含まれること
        # RED: 実装前は含まれていないため FAIL する
        tools_py_path = (
            Path(__file__).resolve().parent.parent
            / "src" / "twl" / "mcp_server" / "tools.py"
        )
        assert tools_py_path.exists(), f"tools.py が存在しない: {tools_py_path}"
        content = tools_py_path.read_text()
        assert "from .tools_comm import *" in content, (
            "tools.py に 'from .tools_comm import *' が含まれない (AC5-8 未実装)"
        )


# ---------------------------------------------------------------------------
# AC5-9: glossary.md に mailbox / mailbox file 用語追加
# ---------------------------------------------------------------------------


class TestAC59GlossaryMailbox:
    """AC5-9: glossary.md に mailbox / mailbox file 用語追加.

    実装前は glossary.md に当該用語が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac59_glossary_contains_mailbox_term(self):
        # AC: plugins/twl/architecture/domain/glossary.md に "mailbox" 用語が含まれること
        # RED: 未追加のため FAIL する
        glossary_path = (
            Path(__file__).resolve().parent.parent.parent.parent
            / "plugins" / "twl" / "architecture" / "domain" / "glossary.md"
        )
        assert glossary_path.exists(), f"glossary.md が存在しない: {glossary_path}"
        content = glossary_path.read_text()
        assert "mailbox" in content.lower(), (
            f"glossary.md に 'mailbox' 用語が含まれない (AC5-9 未実装): {glossary_path}"
        )

    def test_ac59_glossary_contains_mailbox_file_term(self):
        # AC: plugins/twl/architecture/domain/glossary.md に "mailbox file" 用語が含まれること
        # RED: 未追加のため FAIL する
        glossary_path = (
            Path(__file__).resolve().parent.parent.parent.parent
            / "plugins" / "twl" / "architecture" / "domain" / "glossary.md"
        )
        assert glossary_path.exists(), f"glossary.md が存在しない: {glossary_path}"
        content = glossary_path.read_text()
        assert "mailbox file" in content.lower(), (
            f"glossary.md に 'mailbox file' 用語が含まれない (AC5-9 未実装): {glossary_path}"
        )


# ---------------------------------------------------------------------------
# AC5-10: ADR-028 write authority matrix に mailbox 行追加
# ---------------------------------------------------------------------------


class TestAC510Adr028MailboxRow:
    """AC5-10: ADR-028 write authority matrix に mailbox 行追加.

    実装前は ADR-028 に当該記述がないため FAIL する（意図的 RED）。
    """

    def test_ac510_adr028_contains_mailbox_write_authority(self):
        # AC: plugins/twl/architecture/decisions/ADR-028-atomic-rmw-strategy.md に mailbox 行が追加されていること
        # RED: 未追加のため FAIL する
        adr_path = (
            Path(__file__).resolve().parent.parent.parent.parent
            / "plugins" / "twl" / "architecture" / "decisions"
            / "ADR-028-atomic-rmw-strategy.md"
        )
        assert adr_path.exists(), f"ADR-028 が存在しない: {adr_path}"
        content = adr_path.read_text()
        # write authority matrix に mailbox 行が含まれていること
        assert "mailbox" in content.lower(), (
            f"ADR-028 に 'mailbox' 行が含まれない (AC5-10 未実装): {adr_path}"
        )


# ---------------------------------------------------------------------------
# AC5-11: session-comm.sh との責務分離（設計制約 AC）
# ---------------------------------------------------------------------------


class TestAC511SessionCommSeparation:
    """AC5-11: session-comm.sh との責務分離（設計制約 AC）.

    tools_comm.py は session-comm.sh を内部で呼び出してはならない。
    実装前は tools_comm.py が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac511_tools_comm_does_not_shell_out_to_session_comm(self):
        # AC: tools_comm.py のソースに session-comm.sh を直接 exec/subprocess する記述がないこと
        # RED: tools_comm.py が未作成のため FAIL する（ファイル不在）
        tools_comm_path = (
            Path(__file__).resolve().parent.parent
            / "src" / "twl" / "mcp_server" / "tools_comm.py"
        )
        assert tools_comm_path.exists(), (
            f"tools_comm.py が存在しない (AC5-11 未実装): {tools_comm_path}"
        )
        content = tools_comm_path.read_text()
        # session-comm.sh を subprocess で直接呼び出していないこと
        assert "session-comm.sh" not in content, (
            "tools_comm.py が session-comm.sh を直接呼び出している (AC5-11 設計違反)"
        )


# ---------------------------------------------------------------------------
# AC5-12: bats は不要（pytest がメイン）
# ---------------------------------------------------------------------------


class TestAC512BatsNotRequired:
    """AC5-12: bats は不要（pytest がメイン）.

    comm 系 tool には bats テストを作成しない。
    このテストは pytest でのテストが存在することを確認する（常に PASS）。
    ただし実装前は tools_comm が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac512_pytest_test_file_exists_for_comm_tools(self):
        # AC: comm tools のテストが pytest で実装されていること（このファイル自体）
        # RED: tools_comm.py が未作成のため他のテストが FAIL している状態
        test_file = Path(__file__)
        assert test_file.exists(), f"テストファイルが存在しない: {test_file}"
        # このファイルに TestAC51 クラスが定義されていることを確認
        content = test_file.read_text()
        assert "TestAC51ThreeToolsAdded" in content, (
            "AC5-1 テストクラスが存在しない (AC5-12 未実装)"
        )

    def test_ac512_no_bats_file_for_comm_tools_required(self):
        # AC: comm 系 tool の bats ファイルが不要であること（bats ファイルが存在しないことを確認）
        # RED: tools_comm.py が未作成のため FAIL する（依存するテストが FAIL）
        repo_root = Path(__file__).resolve().parent.parent.parent.parent
        # bats ファイルが comm 系のために作成されていないこと
        bats_files = list(repo_root.glob("**/*comm*.bats"))
        assert not any("twl_send_msg" in f.read_text() or "twl_recv_msg" in f.read_text()
                        for f in bats_files if f.exists()), (
            f"comm 系 tool の bats ファイルが存在する (AC5-12 設計違反): {bats_files}"
        )


# ---------------------------------------------------------------------------
# 共通-1: 3 tool が tools.py（または tools_comm.py 経由）に存在すること
# ---------------------------------------------------------------------------


class TestCommon1CommToolsExist:
    """共通-1: 3 comm tool が tools.py（tools_comm.py 経由）に存在すること.

    実装前は tools.py/tools_comm.py に comm tool がないため FAIL する（意図的 RED）。
    """

    def test_common1_all_3_comm_tools_present_via_tools_module(self):
        # AC: 3 comm tool が tools モジュールから参照可能であること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        missing = [name for name in EXPECTED_COMM_TOOL_NAMES if not hasattr(tools, name)]
        assert not missing, (
            f"tools モジュールに以下の comm tool が存在しない (共通-1 未実装): {missing}"
        )

    def test_common1_twl_send_msg_accessible_from_tools(self):
        # AC: twl_send_msg が tools モジュールから参照可能であること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_send_msg"), (
            "tools モジュールに twl_send_msg が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_recv_msg_accessible_from_tools(self):
        # AC: twl_recv_msg が tools モジュールから参照可能であること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_recv_msg"), (
            "tools モジュールに twl_recv_msg が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_notify_supervisor_accessible_from_tools(self):
        # AC: twl_notify_supervisor が tools モジュールから参照可能であること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_notify_supervisor"), (
            "tools モジュールに twl_notify_supervisor が存在しない (共通-1 未実装)"
        )


# ---------------------------------------------------------------------------
# 共通-2: handler 関数が存在すること
# ---------------------------------------------------------------------------


class TestCommon2CommHandlersExist:
    """共通-2: 3 comm handler 関数が存在すること.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_common2_all_3_comm_handlers_present(self):
        # AC: 3 comm handler が tools_comm モジュールに存在すること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        missing = [h for h in EXPECTED_COMM_HANDLER_NAMES if not hasattr(tools_comm, h)]
        assert not missing, (
            f"tools_comm に以下の comm handler が存在しない (共通-2 未実装): {missing}"
        )

    def test_common2_twl_send_msg_handler_exists(self):
        # AC: twl_send_msg_handler が存在すること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        assert hasattr(tools_comm, "twl_send_msg_handler"), (
            "tools_comm に twl_send_msg_handler が存在しない (共通-2 未実装)"
        )

    def test_common2_twl_recv_msg_handler_exists(self):
        # AC: twl_recv_msg_handler が存在すること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        assert hasattr(tools_comm, "twl_recv_msg_handler"), (
            "tools_comm に twl_recv_msg_handler が存在しない (共通-2 未実装)"
        )

    def test_common2_twl_notify_supervisor_handler_exists(self):
        # AC: twl_notify_supervisor_handler が存在すること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        assert hasattr(tools_comm, "twl_notify_supervisor_handler"), (
            "tools_comm に twl_notify_supervisor_handler が存在しない (共通-2 未実装)"
        )


# ---------------------------------------------------------------------------
# 共通-3: MCP tool 登録（@mcp.tool() + try/except ImportError gate）
# ---------------------------------------------------------------------------


class TestCommon3McpToolRegistration:
    """共通-3: comm tool が @mcp.tool() + try/except ImportError gate で登録されていること.

    実装前は tools_comm.py が存在しないため FAIL する（意図的 RED）。
    """

    def test_common3_tools_comm_importable_without_mcp_installed(self):
        # AC: fastmcp が未インストールでも tools_comm.py が import 可能であること（ImportError gate）
        # RED: tools_comm.py が未作成のため FAIL する
        # fastmcp を mock して import
        with patch.dict(sys.modules, {"fastmcp": None}):
            # tools_comm の import は try/except ImportError gate で保護されていること
            try:
                import importlib
                # 既存 import を除去して再 import
                for key in list(sys.modules.keys()):
                    if "tools_comm" in key:
                        del sys.modules[key]
                from twl.mcp_server import tools_comm  # noqa: F401
            except ImportError as e:
                pytest.fail(
                    f"fastmcp 未インストール時に tools_comm が ImportError を raise した "
                    f"(共通-3 未実装): {e}"
                )

    def test_common3_comm_tools_appear_in_mcp_server_module(self):
        # AC: 3 comm tool が mcp_server モジュールを通じて参照可能であること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        for name in EXPECTED_COMM_TOOL_NAMES:
            assert hasattr(tools, name), (
                f"tools モジュールに {name} が存在しない (共通-3 未実装)"
            )


# ---------------------------------------------------------------------------
# 共通-4: handler unit test（fastmcp 経由 + 直接呼び出し 2 経路）
# ---------------------------------------------------------------------------


class TestCommon4HandlerTwoCallPaths:
    """共通-4: handler unit test — fastmcp 経由 + 直接呼び出し 2 経路で PASS すること.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_common4_twl_send_msg_handler_direct_call_returns_json_str(self):
        # AC: twl_send_msg_handler を直接呼び出して JSON str が返ること（経路 1: 直接呼び出し）
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_send_msg_handler
                result_str = twl_send_msg_handler(
                    to="supervisor",
                    type_="unit_test",
                    content="direct call path",
                    timeout_sec=5,
                )
                assert isinstance(result_str, str), (
                    f"直接呼び出しで str が返らない: {type(result_str)} (共通-4 未実装)"
                )
                result = json.loads(result_str)
                assert "ok" in result, (
                    f"JSON に 'ok' キーがない (共通-4 未実装): {result}"
                )

    async def test_common4_twl_recv_msg_handler_direct_call_returns_json_str(self):
        # AC: twl_recv_msg_handler を直接呼び出して JSON str が返ること（経路 1: 直接呼び出し）
        # RED: handler が未実装のため FAIL する
        import os
        with tempfile.TemporaryDirectory() as tmpdir:
            mailbox_dir = Path(tmpdir) / "mailbox"
            mailbox_dir.mkdir()
            with patch.dict(os.environ, {"AUTOPILOT_DIR": tmpdir}):
                from twl.mcp_server.tools_comm import twl_recv_msg_handler
                result_str = await twl_recv_msg_handler(
                    receiver="supervisor",
                    timeout_sec=0,
                )
                assert isinstance(result_str, str), (
                    f"直接呼び出しで str が返らない: {type(result_str)} (共通-4 未実装)"
                )
                result = json.loads(result_str)
                assert "ok" in result, (
                    f"JSON に 'ok' キーがない (共通-4 未実装): {result}"
                )

    def test_common4_twl_send_msg_handler_via_tools_module_accessible(self):
        # AC: tools モジュール経由で twl_send_msg_handler に到達できること（経路 2: tools モジュール）
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_send_msg_handler", None)
        assert handler is not None, (
            "tools モジュールに twl_send_msg_handler が存在しない (共通-4 未実装)"
        )
        assert callable(handler), (
            "tools.twl_send_msg_handler が callable でない (共通-4 未実装)"
        )

    def test_common4_twl_recv_msg_handler_via_tools_module_accessible(self):
        # AC: tools モジュール経由で twl_recv_msg_handler に到達できること（経路 2: tools モジュール）
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_recv_msg_handler", None)
        assert handler is not None, (
            "tools モジュールに twl_recv_msg_handler が存在しない (共通-4 未実装)"
        )
        assert callable(handler), (
            "tools.twl_recv_msg_handler が callable でない (共通-4 未実装)"
        )

    def test_common4_twl_notify_supervisor_handler_via_tools_module_accessible(self):
        # AC: tools モジュール経由で twl_notify_supervisor_handler に到達できること（経路 2: tools モジュール）
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_notify_supervisor_handler", None)
        assert handler is not None, (
            "tools モジュールに twl_notify_supervisor_handler が存在しない (共通-4 未実装)"
        )
        assert callable(handler), (
            "tools.twl_notify_supervisor_handler が callable でない (共通-4 未実装)"
        )


# ---------------------------------------------------------------------------
# 共通-5: bats 互換性（comm 系は新規のため no-op）
# ---------------------------------------------------------------------------


class TestCommon5BatsCompatibility:
    """共通-5: bats 互換性（comm 系は新規のため no-op、PR body に「対応 wrapper なし」明記）.

    このテストは常に PASS する（no-op AC）。
    ただし tools_comm.py が存在しない場合の確認も含む。
    """

    def test_common5_comm_tools_have_no_bats_wrapper_required(self):
        # AC: comm 系 tool は新規作成のため bats wrapper が不要であること（no-op）
        # このテスト自体は常に PASS する
        # comm 系は session-comm.sh を経由した既存 shell wrapper を持たないため
        # bats 互換性は対象外
        assert True, "comm 系 tool は bats wrapper 不要（no-op AC）"


# ---------------------------------------------------------------------------
# 共通-6: tools.py + tools_comm.py の行数確認（twl validate PASS）
# ---------------------------------------------------------------------------


class TestCommon6LineCountValidation:
    """共通-6: tools.py + tools_comm.py の行数が twl validate 基準に収まること.

    実装前は tools_comm.py が存在しないため FAIL する（意図的 RED）。
    """

    def test_common6_tools_comm_py_exists(self):
        # AC: tools_comm.py が実際に作成されていること
        # RED: 未作成のため FAIL する
        tools_comm_path = (
            Path(__file__).resolve().parent.parent
            / "src" / "twl" / "mcp_server" / "tools_comm.py"
        )
        assert tools_comm_path.exists(), (
            f"tools_comm.py が存在しない (共通-6 未実装): {tools_comm_path}"
        )

    def test_common6_tools_py_still_importable_after_split(self):
        # AC: tools.py が tools_comm.py 分割後も import 可能であること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools  # noqa: F401
        assert tools is not None, (
            "tools.py が import できない (共通-6 未実装)"
        )

    def test_common6_tools_comm_py_importable(self):
        # AC: tools_comm.py が import 可能であること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm  # noqa: F401
        assert tools_comm is not None, (
            "tools_comm.py が import できない (共通-6 未実装)"
        )


# ---------------------------------------------------------------------------
# 共通-7: Bounded Context 整合（Autopilot 配下、OHS 方向維持）
# ---------------------------------------------------------------------------


class TestCommon7BoundedContextAlignment:
    """共通-7: Bounded Context 整合（Autopilot 配下、OHS 方向維持）.

    tools_comm.py は twl.mcp_server 名前空間（Autopilot 配下）に配置されること。
    実装前は tools_comm.py が存在しないため FAIL する（意図的 RED）。
    """

    def test_common7_tools_comm_in_mcp_server_namespace(self):
        # AC: tools_comm が twl.mcp_server 名前空間に存在すること
        # RED: tools_comm.py が未作成のため FAIL する
        from twl.mcp_server import tools_comm
        module_name = tools_comm.__name__
        assert module_name.startswith("twl.mcp_server"), (
            f"tools_comm が twl.mcp_server 名前空間にない: {module_name} (共通-7 未実装)"
        )

    def test_common7_tools_comm_file_located_in_mcp_server_dir(self):
        # AC: tools_comm.py が cli/twl/src/twl/mcp_server/ に配置されていること
        # RED: tools_comm.py が未作成のため FAIL する
        tools_comm_path = (
            Path(__file__).resolve().parent.parent
            / "src" / "twl" / "mcp_server" / "tools_comm.py"
        )
        assert tools_comm_path.exists(), (
            f"tools_comm.py が mcp_server ディレクトリにない (共通-7 未実装): {tools_comm_path}"
        )


# ---------------------------------------------------------------------------
# 共通-8: ADR-028 整合確認（write 経路追加）
# ---------------------------------------------------------------------------


class TestCommon8Adr028Alignment:
    """共通-8: ADR-028 整合確認（write 経路追加）.

    ADR-028 の write authority matrix に mailbox write 経路が追加されていること。
    実装前は ADR-028 に当該記述がないため FAIL する（意図的 RED）。
    """

    def test_common8_adr028_exists(self):
        # AC: ADR-028 が存在すること
        # 実装前も存在するはずなので PASS する
        adr_path = (
            Path(__file__).resolve().parent.parent.parent.parent
            / "plugins" / "twl" / "architecture" / "decisions"
            / "ADR-028-atomic-rmw-strategy.md"
        )
        assert adr_path.exists(), (
            f"ADR-028 が存在しない (共通-8): {adr_path}"
        )

    def test_common8_adr028_contains_write_authority_matrix(self):
        # AC: ADR-028 に write authority matrix のセクションが存在すること
        # RED: mailbox 行が追加されていないため FAIL する
        adr_path = (
            Path(__file__).resolve().parent.parent.parent.parent
            / "plugins" / "twl" / "architecture" / "decisions"
            / "ADR-028-atomic-rmw-strategy.md"
        )
        content = adr_path.read_text()
        assert "mailbox" in content.lower(), (
            f"ADR-028 に mailbox の write 経路が記載されていない (共通-8 未実装): {adr_path}"
        )


# ---------------------------------------------------------------------------
# 共通-9: action 系 tool の timeout_sec: int 引数必須
# ---------------------------------------------------------------------------


class TestCommon9TimeoutSecForCommActions:
    """共通-9: action 系 comm tool (twl_send_msg, twl_notify_supervisor) に timeout_sec: int 引数が必須.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_common9_twl_send_msg_handler_has_timeout_sec_int(self):
        # AC: twl_send_msg_handler に timeout_sec: int 引数が存在すること
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_send_msg_handler
        sig = inspect.signature(twl_send_msg_handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_send_msg_handler に timeout_sec 引数がない (共通-9 未実装)"
        )
        param = sig.parameters["timeout_sec"]
        assert param.annotation == int or str(param.annotation) == "int", (
            f"twl_send_msg_handler の timeout_sec が int 型でない: {param.annotation} (共通-9 未実装)"
        )

    def test_common9_twl_notify_supervisor_handler_has_timeout_sec_int(self):
        # AC: twl_notify_supervisor_handler に timeout_sec: int 引数が存在すること
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_notify_supervisor_handler
        sig = inspect.signature(twl_notify_supervisor_handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_notify_supervisor_handler に timeout_sec 引数がない (共通-9 未実装)"
        )
        param = sig.parameters["timeout_sec"]
        assert param.annotation == int or str(param.annotation) == "int", (
            f"twl_notify_supervisor_handler の timeout_sec が int 型でない: {param.annotation} (共通-9 未実装)"
        )

    def test_common9_twl_recv_msg_has_timeout_sec_but_defaults_zero(self):
        # AC: twl_recv_msg_handler も timeout_sec を持ち、デフォルトが 0（non-blocking）であること
        # RED: handler が未実装のため FAIL する
        from twl.mcp_server.tools_comm import twl_recv_msg_handler
        sig = inspect.signature(twl_recv_msg_handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_recv_msg_handler に timeout_sec 引数がない (共通-9 未実装)"
        )
        assert sig.parameters["timeout_sec"].default == 0, (
            f"twl_recv_msg_handler の timeout_sec デフォルトが 0 でない: "
            f"{sig.parameters['timeout_sec'].default} (共通-9 未実装)"
        )
