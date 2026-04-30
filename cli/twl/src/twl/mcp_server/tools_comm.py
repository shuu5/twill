"""twl MCP comm tools: twl_send_msg, twl_recv_msg, twl_notify_supervisor.

File-based jsonl + flock mailbox hub (ADR-028 §Implementation, AC5-2).
Handler functions (_handler suffix) are pure Python, return JSON str directly.
"""
from __future__ import annotations

import asyncio
import fcntl
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path

__all__ = [
    "twl_send_msg_handler",
    "twl_recv_msg_handler",
    "twl_notify_supervisor_handler",
    "twl_send_msg",
    "twl_recv_msg",
    "twl_notify_supervisor",
]

_RECEIVER_RE = re.compile(r"^[a-zA-Z0-9_\-:]+$")
_KNOWN_PREFIXES = ("pilot:", "worker:", "sibling:")
_SUPERVISOR_NAME = "supervisor"

# Crockford base32 alphabet for ULID generation (no external dep)
_B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def _b32_encode(n: int, width: int) -> str:
    buf = []
    for _ in range(width):
        buf.append(_B32[n & 31])
        n >>= 5
    return "".join(reversed(buf))


def _generate_ulid() -> str:
    ts_ms = int(time.time() * 1000)
    return _b32_encode(ts_ms, 10) + _b32_encode(
        int.from_bytes(os.urandom(10), "big"), 16
    )


def _validate_receiver(name: str) -> bool:
    return bool(_RECEIVER_RE.match(name))


def _is_known_receiver(name: str) -> bool:
    return name == _SUPERVISOR_NAME or any(
        name.startswith(p) for p in _KNOWN_PREFIXES
    )


def _mailbox_dir(autopilot_dir: str | None) -> Path:
    base = Path(autopilot_dir or os.environ.get("AUTOPILOT_DIR", ".autopilot"))
    return base / "mailbox"


def _append_atomic(mailbox_path: Path, msg: dict) -> None:
    """Append msg as JSON line with flock protection (ADR-028)."""
    lock_path = mailbox_path.with_suffix(mailbox_path.suffix + ".lock")
    lock_path.touch(mode=0o600, exist_ok=True)
    os.chmod(lock_path, 0o600)  # touch() ignores mode on existing files (Python spec)
    with open(lock_path, "a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            opener = lambda p, flags: os.open(p, flags, 0o600)
            with open(mailbox_path, "a", opener=opener) as mf:
                mf.write(json.dumps(msg, ensure_ascii=False) + "\n")
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)


def _parse_since(since: str) -> tuple[str | None, datetime | None]:
    """Return (ulid, datetime) tuple; both None means invalid format."""
    # ULID: 26 chars, Crockford base32
    if len(since) == 26 and re.match(r"^[0-9A-HJKMNP-TV-Z]+$", since, re.IGNORECASE):
        return since, None
    # RFC3339 UTC
    try:
        dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            raise ValueError("missing tzinfo")
        return None, dt.astimezone(timezone.utc)
    except Exception:
        return None, None


def _read_since(mailbox_path: Path, since: str | None) -> list[dict]:
    if not mailbox_path.exists():
        return []

    lines: list[dict] = []
    with open(mailbox_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                lines.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    if since is None:
        return lines

    ulid_since, dt_since = _parse_since(since)

    if ulid_since:
        result: list[dict] = []
        found = False
        for msg in lines:
            if found:
                result.append(msg)
            elif msg.get("id") == ulid_since:
                found = True
        # Fallback when ULID not found (mailbox rotated/truncated): return all to avoid zero-loss violation
        return result if found else lines

    if dt_since:
        result = []
        for msg in lines:
            try:
                msg_dt = datetime.fromisoformat(
                    msg.get("ts", "").replace("Z", "+00:00")
                ).astimezone(timezone.utc)
                if msg_dt > dt_since:
                    result.append(msg)
            except Exception:
                continue
        return result

    return lines


# ---------------------------------------------------------------------------
# Private implementation functions (return dict)
# ---------------------------------------------------------------------------

def _send_msg_impl(
    to: str,
    type_: str,
    content: str,
    reply_to: str | None,
    timeout_sec: int,  # reserved for future use; file-write is fire-and-forget
    autopilot_dir: str | None,
) -> dict:
    if not _validate_receiver(to):
        return {"ok": False, "error_type": "invalid_receiver", "exit_code": 3}
    if not _is_known_receiver(to):
        return {"ok": False, "error_type": "unknown_receiver", "exit_code": 3}

    mdir = _mailbox_dir(autopilot_dir)
    mdir.mkdir(parents=True, exist_ok=True)

    mailbox_path = mdir / f"{to}.jsonl"
    msg_id = _generate_ulid()
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    msg = {
        "id": msg_id,
        "ts": ts,
        "to": to,
        "type": type_,
        "content": content,
        "reply_to": reply_to,
    }

    try:
        _append_atomic(mailbox_path, msg)
        return {"ok": True, "id": msg_id, "exit_code": 0}
    except Exception:
        return {"ok": False, "error_type": "write_error", "error": "mailbox write failed", "exit_code": 1}


async def _recv_msg_impl(
    receiver: str,
    since: str | None,
    timeout_sec: int,
    autopilot_dir: str | None,
) -> dict:
    if not _validate_receiver(receiver):
        return {"ok": False, "error_type": "invalid_receiver", "exit_code": 3}

    if since is not None:
        ulid_s, dt_s = _parse_since(since)
        if ulid_s is None and dt_s is None:
            return {"ok": False, "error_type": "invalid_since", "exit_code": 3}

    if timeout_sec < 0:
        return {"ok": False, "error_type": "invalid_timeout", "exit_code": 3}
    mailbox_path = _mailbox_dir(autopilot_dir) / f"{receiver}.jsonl"
    deadline = time.monotonic() + timeout_sec

    while True:
        msgs = _read_since(mailbox_path, since)  # sync IO: mailbox is small (<KB), blocking time is negligible
        if msgs or timeout_sec == 0:
            return {"ok": True, "msgs": msgs, "exit_code": 0}
        if time.monotonic() >= deadline:
            return {"ok": True, "msgs": [], "exit_code": 0}
        await asyncio.sleep(0.1)


# ---------------------------------------------------------------------------
# Handler functions (pure Python, _handler suffix, return JSON str)
# ---------------------------------------------------------------------------


def twl_send_msg_handler(
    to: str,
    type_: str,
    content: str,
    reply_to: str | None = None,
    timeout_sec: int = 10,
    autopilot_dir: str | None = None,
) -> str:
    return json.dumps(
        _send_msg_impl(to, type_, content, reply_to, timeout_sec, autopilot_dir),
        ensure_ascii=False,
    )


async def twl_recv_msg_handler(
    receiver: str,
    since: str | None = None,
    timeout_sec: int = 0,
    autopilot_dir: str | None = None,
) -> str:
    return json.dumps(
        await _recv_msg_impl(receiver, since, timeout_sec, autopilot_dir),
        ensure_ascii=False,
    )


def twl_notify_supervisor_handler(
    event: str,
    payload: dict,
    timeout_sec: int = 10,
    autopilot_dir: str | None = None,
) -> str:
    return json.dumps(
        _send_msg_impl(
            to=_SUPERVISOR_NAME,
            type_=event,
            content=json.dumps(payload, ensure_ascii=False),
            reply_to=None,
            timeout_sec=timeout_sec,
            autopilot_dir=autopilot_dir,
        ),
        ensure_ascii=False,
    )


# ---------------------------------------------------------------------------
# MCP tool registration — requires fastmcp (optional dep)
# ---------------------------------------------------------------------------

try:
    from fastmcp import FastMCP as _FastMCP

    _mcp_comm = _FastMCP("twl-comm")

    @_mcp_comm.tool()
    def twl_send_msg(
        to: str,
        type_: str,
        content: str,
        reply_to: str | None = None,
        timeout_sec: int = 10,
        autopilot_dir: str | None = None,
    ) -> str:
        """Send a message to a named receiver via file-based jsonl mailbox. Note: set MCP_CLIENT_TIMEOUT>=20s."""
        return twl_send_msg_handler(
            to=to, type_=type_, content=content,
            reply_to=reply_to, timeout_sec=timeout_sec,
            autopilot_dir=autopilot_dir,
        )

    @_mcp_comm.tool()
    async def twl_recv_msg(
        receiver: str,
        since: str | None = None,
        timeout_sec: int = 0,
        autopilot_dir: str | None = None,
    ) -> str:
        """Receive messages from mailbox. timeout_sec=0: non-blocking poll; >0: blocking wait. Note: set MCP_CLIENT_TIMEOUT>=(timeout_sec+10)s."""
        return await twl_recv_msg_handler(
            receiver=receiver, since=since,
            timeout_sec=timeout_sec, autopilot_dir=autopilot_dir,
        )

    @_mcp_comm.tool()
    def twl_notify_supervisor(
        event: str,
        payload: dict,
        timeout_sec: int = 10,
        autopilot_dir: str | None = None,
    ) -> str:
        """Notify observer/supervisor with an event + payload via mailbox. Note: set MCP_CLIENT_TIMEOUT>=20s."""
        return twl_notify_supervisor_handler(
            event=event, payload=payload,
            timeout_sec=timeout_sec, autopilot_dir=autopilot_dir,
        )

except ImportError:
    def twl_send_msg(  # type: ignore[misc]
        to: str,
        type_: str,
        content: str,
        reply_to: str | None = None,
        timeout_sec: int = 10,
        autopilot_dir: str | None = None,
    ) -> str:
        """Send a message to a named receiver via file-based jsonl mailbox (fastmcp not installed)."""
        return twl_send_msg_handler(
            to=to, type_=type_, content=content,
            reply_to=reply_to, timeout_sec=timeout_sec,
            autopilot_dir=autopilot_dir,
        )

    async def twl_recv_msg(  # type: ignore[misc]
        receiver: str,
        since: str | None = None,
        timeout_sec: int = 0,
        autopilot_dir: str | None = None,
    ) -> str:
        """Receive messages from mailbox (fastmcp not installed)."""
        return await twl_recv_msg_handler(
            receiver=receiver, since=since,
            timeout_sec=timeout_sec, autopilot_dir=autopilot_dir,
        )

    def twl_notify_supervisor(  # type: ignore[misc]
        event: str,
        payload: dict,
        timeout_sec: int = 10,
        autopilot_dir: str | None = None,
    ) -> str:
        """Notify observer/supervisor with an event + payload via mailbox (fastmcp not installed)."""
        return twl_notify_supervisor_handler(
            event=event, payload=payload,
            timeout_sec=timeout_sec, autopilot_dir=autopilot_dir,
        )
