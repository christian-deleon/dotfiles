#!/usr/bin/env python3
"""Stdio MCP shim: strip aws___ tool prefixes so Grok can register them.

Grok namespaces MCP tools as server__tool. The managed AWS MCP server already
names tools aws___call_aws, which the session registry drops (0 tools). This
process sits in front of mcp-proxy-for-aws, rewrites tools/list names to
call_aws, and maps tools/call back.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import threading
from copy import deepcopy
from typing import Any

PREFIX = "aws___"

JsonObject = dict[str, Any]


class NameMap:
    """Grok-facing tool name -> backend tool name."""

    def __init__(self) -> None:
        self._to_backend: dict[str, str] = {}

    def remember(self, backend_name: str) -> str:
        grok_name = backend_name.removeprefix(PREFIX)
        self._to_backend[grok_name] = backend_name
        return grok_name

    def to_backend(self, grok_name: str) -> str:
        mapped = self._to_backend.get(grok_name)
        if mapped is not None:
            return mapped
        if grok_name.startswith(PREFIX):
            return grok_name
        return PREFIX + grok_name


def _scrub_tool(tool: JsonObject, names: NameMap) -> None:
    backend = tool.get("name")
    if isinstance(backend, str):
        tool["name"] = names.remember(backend)
    tool.pop("_meta", None)
    tool.pop("outputSchema", None)


def rewrite_server_message(msg: JsonObject, names: NameMap) -> JsonObject:
    """Rewrite a JSON-RPC message from the AWS proxy toward Grok."""
    result = msg.get("result")
    if not isinstance(result, dict):
        return msg
    tools = result.get("tools")
    if not isinstance(tools, list):
        return msg
    out = deepcopy(msg)
    out_tools = out["result"]["tools"]
    for tool in out_tools:
        if isinstance(tool, dict):
            _scrub_tool(tool, names)
    return out


def rewrite_client_message(msg: JsonObject, names: NameMap) -> JsonObject:
    """Rewrite a JSON-RPC message from Grok toward the AWS proxy."""
    if msg.get("method") != "tools/call":
        return msg
    params = msg.get("params")
    if not isinstance(params, dict):
        return msg
    grok_name = params.get("name")
    if not isinstance(grok_name, str):
        return msg
    out = deepcopy(msg)
    out["params"]["name"] = names.to_backend(grok_name)
    return out


def _forward_stderr(src: Any) -> None:
    try:
        while True:
            chunk = src.read(4096)
            if not chunk:
                return
            sys.stderr.buffer.write(chunk)
            sys.stderr.buffer.flush()
    except OSError:
        return


def _relay_stdout(src: Any, names: NameMap) -> None:
    try:
        while True:
            raw = src.readline()
            if not raw:
                return
            line = raw.decode("utf-8", errors="replace")
            stripped = line.strip()
            if not stripped:
                sys.stdout.write(line)
                sys.stdout.flush()
                continue
            try:
                msg = json.loads(stripped)
            except json.JSONDecodeError:
                sys.stdout.write(line)
                sys.stdout.flush()
                continue
            if isinstance(msg, dict):
                msg = rewrite_server_message(msg, names)
            sys.stdout.write(json.dumps(msg, separators=(",", ":")) + "\n")
            sys.stdout.flush()
    except OSError:
        return


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: aws_mcp_grok_shim.py <command> [args...]",
            file=sys.stderr,
        )
        return 2
    names = NameMap()
    child = subprocess.Popen(
        argv[1:],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    if child.stdin is None or child.stdout is None or child.stderr is None:
        print("aws_mcp_grok_shim: failed to create child pipes", file=sys.stderr)
        child.kill()
        return 1

    def _forward_signal(signum: int, _frame: Any) -> None:
        if child.poll() is None:
            child.send_signal(signum)

    signal.signal(signal.SIGTERM, _forward_signal)
    signal.signal(signal.SIGINT, _forward_signal)

    threading.Thread(target=_forward_stderr, args=(child.stderr,), daemon=True).start()
    threading.Thread(
        target=_relay_stdout, args=(child.stdout, names), daemon=True
    ).start()

    try:
        for raw in sys.stdin.buffer:
            line = raw.decode("utf-8", errors="replace")
            stripped = line.strip()
            if not stripped:
                child.stdin.write(raw)
                child.stdin.flush()
                continue
            try:
                msg = json.loads(stripped)
            except json.JSONDecodeError:
                child.stdin.write(raw)
                child.stdin.flush()
                continue
            if isinstance(msg, dict):
                msg = rewrite_client_message(msg, names)
            payload = (json.dumps(msg, separators=(",", ":")) + "\n").encode()
            child.stdin.write(payload)
            child.stdin.flush()
    except BrokenPipeError:
        pass
    finally:
        try:
            child.stdin.close()
        except OSError:
            pass
    return child.wait()


if __name__ == "__main__":
    os.environ.setdefault("PYTHONUNBUFFERED", "1")
    raise SystemExit(main(sys.argv))
