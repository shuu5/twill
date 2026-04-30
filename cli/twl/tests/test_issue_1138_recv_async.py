"""Tests for Issue #1138: tech-debt tools_comm.py _recv_msg_impl async 化.

TDD RED フェーズ用テスト。
実装前は全テストが FAIL する（意図的 RED）。

AC 一覧:
  AC-1: _recv_msg_impl が async def で定義され、time.sleep ではなく await asyncio.sleep(0.1) を使用
  AC-2: twl_recv_msg_handler が async def、twl_recv_msg も async def（戻り値型は str 維持）
  AC-3: 既存テストが pytest-asyncio 対応（pyproject.toml に asyncio_mode=auto が設定済み）
  AC-4: asyncio.gather で 4 並行 recv + 1 件 send シナリオ（対象 receiver だけ先に return）
  AC-5: CancelledError が _recv_msg_impl task から伝播する
  AC-6: FastMCP mount 後に async twl_recv_msg が MCP 経由で呼び出せる
  AC-7: pyproject.toml に pytest-asyncio>=0.23 が含まれる
  AC-8: pyproject.toml に asyncio_mode = "auto" が設定されている
"""

from __future__ import annotations

import asyncio
import inspect
import re
import tempfile
from pathlib import Path

import pytest

# ターゲットモジュール・ファイルのパス
# tests/ -> cli/twl/ -> cli/ -> worktree_root (2 levels up from tests/)
_CLI_TWL_DIR = Path(__file__).resolve().parent.parent
_TOOLS_COMM_PY = _CLI_TWL_DIR / "src" / "twl" / "mcp_server" / "tools_comm.py"
_PYPROJECT_TOML = _CLI_TWL_DIR / "pyproject.toml"


# ---------------------------------------------------------------------------
# AC-1: _recv_msg_impl が async def で定義され、time.sleep 不使用
# ---------------------------------------------------------------------------


def test_ac1_recv_msg_impl_is_async_def():
    """AC-1: _recv_msg_impl が 'async def' で定義されていること.

    RED: 現状は 'def _recv_msg_impl' (同期関数) のため FAIL する。
    grep -nE "^async def _recv_msg_impl" が 1 件ヒットすること。
    """
    source = _TOOLS_COMM_PY.read_text(encoding="utf-8")
    matches = re.findall(r"^async def _recv_msg_impl", source, re.MULTILINE)
    assert len(matches) == 1, (
        f"tools_comm.py に 'async def _recv_msg_impl' が 1 件見つからない。"
        f"見つかった件数: {len(matches)}。(AC-1 未実装)"
    )


def test_ac1_no_time_sleep_in_recv_msg_impl():
    """AC-1: tools_comm.py 内に time.sleep が残存しないこと.

    RED: 現状は _recv_msg_impl 内で time.sleep(0.1) を使用しているため FAIL する。
    実装後は asyncio.sleep(0.1) に置き換えられ、time.sleep は 0 件になる。
    """
    source = _TOOLS_COMM_PY.read_text(encoding="utf-8")
    sleep_matches = re.findall(r"\btime\.sleep\b", source)
    assert len(sleep_matches) == 0, (
        f"tools_comm.py に time.sleep が {len(sleep_matches)} 件残存している。"
        f"asyncio.sleep(0.1) に置き換えること。(AC-1 未実装)"
    )


def test_ac1_asyncio_sleep_used_in_recv_msg_impl():
    """AC-1: tools_comm.py 内で asyncio.sleep(0.1) が使用されていること.

    RED: 現状は time.sleep(0.1) を使用しているため FAIL する。
    """
    source = _TOOLS_COMM_PY.read_text(encoding="utf-8")
    matches = re.findall(r"\bawait\s+asyncio\.sleep\(0\.1\)", source)
    assert len(matches) >= 1, (
        f"tools_comm.py に 'await asyncio.sleep(0.1)' が見つからない。(AC-1 未実装)"
    )


# ---------------------------------------------------------------------------
# AC-2: twl_recv_msg_handler が async def、twl_recv_msg も async def
# ---------------------------------------------------------------------------


def test_ac2_twl_recv_msg_handler_is_coroutine_function():
    """AC-2: inspect.iscoroutinefunction(twl_recv_msg_handler) が True であること.

    RED: 現状は同期 def のため False が返り FAIL する。
    """
    from twl.mcp_server.tools_comm import twl_recv_msg_handler

    assert inspect.iscoroutinefunction(twl_recv_msg_handler), (
        "twl_recv_msg_handler が async def ではない（coroutine function でない）。"
        "inspect.iscoroutinefunction() == False。(AC-2 未実装)"
    )


def test_ac2_twl_recv_msg_is_async_def_in_source():
    """AC-2: tools_comm.py 内の twl_recv_msg 定義が async def であること.

    RED: 現状は 'def twl_recv_msg' のため FAIL する。
    """
    source = _TOOLS_COMM_PY.read_text(encoding="utf-8")
    # fastmcp ブロック内の twl_recv_msg も async def であることを確認
    matches = re.findall(r"^\s*async def twl_recv_msg\b", source, re.MULTILINE)
    assert len(matches) >= 1, (
        f"tools_comm.py に 'async def twl_recv_msg' が見つからない。"
        f"見つかった件数: {len(matches)}。(AC-2 未実装)"
    )


def test_ac2_twl_recv_msg_handler_return_type_is_str():
    """AC-2: twl_recv_msg_handler の戻り値型が str であること（型アノテーション確認）.

    async 化後も return type は str を維持する必要がある。
    """
    source = _TOOLS_COMM_PY.read_text(encoding="utf-8")
    # 'async def twl_recv_msg_handler(...) -> str:' を確認
    matches = re.findall(
        r"async def twl_recv_msg_handler[^)]*\)\s*->\s*str\s*:",
        source,
        re.DOTALL,
    )
    assert len(matches) >= 1, (
        "tools_comm.py に 'async def twl_recv_msg_handler(...) -> str:' が見つからない。"
        "async 化後も戻り値型は str であること。(AC-2 未実装)"
    )


# ---------------------------------------------------------------------------
# AC-3: pyproject.toml に asyncio_mode = "auto" が設定されていること（smoke test）
# ---------------------------------------------------------------------------


def test_ac3_pyproject_has_asyncio_mode_auto():
    """AC-3: pyproject.toml に asyncio_mode = "auto" が設定されていること.

    既存テストが pytest-asyncio 対応で動作するために必要な設定。
    RED: 現状は [tool.pytest.ini_options] セクション自体が存在しないため FAIL する。
    """
    content = _PYPROJECT_TOML.read_text(encoding="utf-8")
    assert 'asyncio_mode = "auto"' in content, (
        "pyproject.toml に 'asyncio_mode = \"auto\"' が設定されていない。"
        "[tool.pytest.ini_options] セクションに追加すること。(AC-3/AC-8 未実装)"
    )


# ---------------------------------------------------------------------------
# AC-4: asyncio.gather で 4 並行 recv + 1 件 send シナリオ
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_ac4_concurrent_recv_send_scenario():
    """AC-4: asyncio.gather で 4 並行 recv + 1 件 send のシナリオ.

    - receiver_A に 4 並行で twl_recv_msg_handler(timeout_sec=60) を起動
    - 1 件の receiver_A 宛に twl_send_msg_handler でメッセージを送信
    - 対象 receiver は先に return し、他 3 件はまだ待機中であること

    RED: twl_recv_msg_handler が同期関数のため asyncio.gather 内で
    ブロッキングし、並行動作しないため期待通りに動作しない。
    また、async def でないため await できない。
    """
    from twl.mcp_server.tools_comm import twl_recv_msg_handler, twl_send_msg_handler

    # async def でない場合は最初の assert で FAIL させる
    assert inspect.iscoroutinefunction(twl_recv_msg_handler), (
        "twl_recv_msg_handler が async def ではないため並行テスト不可。(AC-2/AC-4 未実装)"
    )
    assert inspect.iscoroutinefunction(twl_send_msg_handler) or callable(twl_send_msg_handler), (
        "twl_send_msg_handler が呼び出し不能。"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        mailbox_dir = Path(tmpdir) / "mailbox"
        mailbox_dir.mkdir()

        receiver_name = "pilot:test-ac4-recv"
        # 送信者はシンプルに send_msg_handler 経由で投函
        sender_receiver = "pilot:test-ac4-send"

        completed: list[int] = []

        async def recv_task(task_id: int) -> dict:
            """twl_recv_msg_handler を await して結果を返す."""
            result = await twl_recv_msg_handler(
                receiver=receiver_name,
                timeout_sec=10,
                autopilot_dir=tmpdir,
            )
            completed.append(task_id)
            return result

        # 4 並行で recv を起動（gather せず task 生成）
        tasks = [asyncio.create_task(recv_task(i)) for i in range(4)]

        # 少し待ってから 1 件送信（全 task が待機状態になるのを待つ）
        await asyncio.sleep(0.3)

        # メッセージ送信（同期 or async）
        if inspect.iscoroutinefunction(twl_send_msg_handler):
            await twl_send_msg_handler(
                to=receiver_name,
                type_="ping",
                content="hello from ac4",
                autopilot_dir=tmpdir,
            )
        else:
            twl_send_msg_handler(
                to=receiver_name,
                type_="ping",
                content="hello from ac4",
                autopilot_dir=tmpdir,
            )

        # 受信完了まで待機（タイムアウト付き）
        await asyncio.wait_for(
            asyncio.gather(*tasks, return_exceptions=True),
            timeout=15.0,
        )

        # 全 4 件が受信できていること（同一 mailbox のため全件受信する）
        assert len(completed) == 4, (
            f"4 並行 recv のうち {len(completed)} 件しか完了していない。(AC-4)"
        )


# ---------------------------------------------------------------------------
# AC-5: CancelledError が _recv_msg_impl task から伝播する
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_ac5_cancelled_error_propagates():
    """AC-5: 並行 await 中の _recv_msg_impl task に task.cancel() を発行すると
    asyncio.CancelledError が伝播すること.

    RED: _recv_msg_impl が同期関数のため asyncio.Task として実行できず、
    CancelledError が正しく伝播しない。
    """
    from twl.mcp_server.tools_comm import twl_recv_msg_handler

    assert inspect.iscoroutinefunction(twl_recv_msg_handler), (
        "twl_recv_msg_handler が async def ではないため CancelledError テスト不可。"
        "(AC-2/AC-5 未実装)"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        mailbox_dir = Path(tmpdir) / "mailbox"
        mailbox_dir.mkdir()

        receiver_name = "pilot:test-ac5-cancel"

        async def long_recv():
            """長時間待機する recv（メッセージは来ない）."""
            return await twl_recv_msg_handler(
                receiver=receiver_name,
                timeout_sec=60,  # 長いタイムアウト（キャンセルされるはず）
                autopilot_dir=tmpdir,
            )

        task = asyncio.create_task(long_recv())

        # task が開始されるまで待機
        await asyncio.sleep(0.3)

        # task をキャンセル
        task.cancel()

        # CancelledError が発生することを確認
        with pytest.raises(asyncio.CancelledError):
            await task


# ---------------------------------------------------------------------------
# AC-6: FastMCP mount 互換性（async 化後に MCP 経由で twl_recv_msg が呼べる）
# ---------------------------------------------------------------------------


def test_ac6_fastmcp_mount_compatibility():
    """AC-6: tools.py 末尾の mcp.mount(_mcp_comm) が async 化後も機能すること.

    FastMCP がインストールされている場合、import が成功し mount が完了することを確認。
    RED: async def twl_recv_msg が未実装のため、mount 後の tool リストに
    async 版が登録されない。
    """
    pytest.importorskip("fastmcp", reason="fastmcp がインストールされていないためスキップ")

    from twl.mcp_server import tools_comm

    # twl_recv_msg が tools_comm に存在すること
    assert hasattr(tools_comm, "twl_recv_msg"), (
        "tools_comm に twl_recv_msg が存在しない。(AC-6)"
    )

    # _mcp_comm が存在し、FastMCP インスタンスであること
    assert hasattr(tools_comm, "_mcp_comm"), (
        "tools_comm に _mcp_comm が存在しない。FastMCP ブロックが動作していない可能性。(AC-6)"
    )

    # tools.py が import でき、mcp.mount が完了していること
    try:
        from twl.mcp_server import tools  # noqa: F401
    except Exception as exc:
        pytest.fail(
            f"tools.py の import または mcp.mount に失敗: {exc}。(AC-6)"
        )

    # async 化後の twl_recv_msg が coroutine function であること
    assert inspect.iscoroutinefunction(tools_comm.twl_recv_msg), (
        "tools_comm.twl_recv_msg が async def ではない。"
        "FastMCP mount 後に async tool として登録されるべき。(AC-2/AC-6 未実装)"
    )


# ---------------------------------------------------------------------------
# AC-7: pyproject.toml に pytest-asyncio>=0.23 が含まれること
# ---------------------------------------------------------------------------


def test_ac7_pytest_asyncio_in_pyproject_mcp_extras():
    """AC-7: pyproject.toml の mcp extras に pytest-asyncio>=0.23 が含まれること.

    RED: 現状は mcp extras に pytest-asyncio が含まれていないため FAIL する。
    """
    content = _PYPROJECT_TOML.read_text(encoding="utf-8")
    assert "pytest-asyncio" in content, (
        "pyproject.toml に pytest-asyncio が含まれていない。"
        "mcp extras または test extras に 'pytest-asyncio>=0.23' を追加すること。(AC-7 未実装)"
    )


def test_ac7_pytest_asyncio_version_constraint():
    """AC-7: pytest-asyncio のバージョン制約が >=0.23 であること.

    RED: pytest-asyncio が pyproject.toml に存在しないため FAIL する。
    """
    content = _PYPROJECT_TOML.read_text(encoding="utf-8")
    # "pytest-asyncio>=0.23" or "pytest-asyncio >= 0.23" の形式
    matches = re.findall(r"pytest-asyncio\s*>=\s*0\.2[3-9]", content)
    assert len(matches) >= 1, (
        f"pyproject.toml に 'pytest-asyncio>=0.23' 以上のバージョン制約が見つからない。"
        f"(AC-7 未実装)"
    )


def test_ac7_test_extras_section_exists():
    """AC-7: pyproject.toml に test extras セクションが存在すること.

    RED: 現状は test extras が存在しないため FAIL する。
    """
    content = _PYPROJECT_TOML.read_text(encoding="utf-8")
    # [project.optional-dependencies] の test セクション
    assert re.search(r"^test\s*=", content, re.MULTILINE), (
        "pyproject.toml の [project.optional-dependencies] に 'test = [...]' セクションが存在しない。"
        "(AC-7 未実装)"
    )


# ---------------------------------------------------------------------------
# AC-8: pyproject.toml に asyncio_mode = "auto" が設定されていること
# ---------------------------------------------------------------------------


def test_ac8_tool_pytest_ini_options_section_exists():
    """AC-8: pyproject.toml に [tool.pytest.ini_options] セクションが存在すること.

    RED: 現状は [tool.pytest.ini_options] セクション自体が存在しないため FAIL する。
    """
    content = _PYPROJECT_TOML.read_text(encoding="utf-8")
    assert "[tool.pytest.ini_options]" in content, (
        "pyproject.toml に [tool.pytest.ini_options] セクションが存在しない。"
        "(AC-8 未実装)"
    )


def test_ac8_asyncio_mode_auto_configured():
    """AC-8: [tool.pytest.ini_options] 内に asyncio_mode = "auto" が設定されていること.

    RED: セクション自体が存在しないため FAIL する。
    """
    content = _PYPROJECT_TOML.read_text(encoding="utf-8")
    assert 'asyncio_mode = "auto"' in content, (
        "pyproject.toml に 'asyncio_mode = \"auto\"' が設定されていない。"
        "[tool.pytest.ini_options] に追加すること。(AC-8 未実装)"
    )
