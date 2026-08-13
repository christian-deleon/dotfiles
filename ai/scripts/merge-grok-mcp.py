#!/usr/bin/env python3
# Merge MCP servers into live ~/.grok/config.toml and force Claude compat off.
#
# Usage:
#   merge-grok-mcp.py <config.toml>
#   merge-grok-mcp.py <config.toml> --mcp <resolved.json> --enabled <enabled.json>
#
# Stdlib only. Splices [mcp_servers.*] and [compat.claude] tables so the rest
# of the live file (which Grok mutates) is left byte-for-byte intact.

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

TABLE_RE = re.compile(r"^\[\[?([^]]+)\]\]?\s*(?:#.*)?$")


def parse_tables(text: str) -> tuple[list[str], list[tuple[str | None, bool, list[str]]]]:
    """Split TOML into preamble lines + (header, is_array_table, lines) tables."""
    preamble: list[str] = []
    tables: list[tuple[str | None, bool, list[str]]] = []
    header: str | None = None
    is_aot = False
    buf: list[str] = []

    def flush() -> None:
        nonlocal header, is_aot, buf
        if header is not None:
            tables.append((header, is_aot, buf))
        header = None
        is_aot = False
        buf = []

    for line in text.splitlines(keepends=True):
        m = TABLE_RE.match(line)
        if m:
            flush()
            header = m.group(1)
            is_aot = line.lstrip().startswith("[[")
            buf = [line]
        elif header is None:
            preamble.append(line)
        else:
            buf.append(line)
    flush()
    return preamble, tables


def keep_table(header: str | None, *, strip_mcp: bool) -> bool:
    if header is None:
        return True
    if strip_mcp and (header == "mcp_servers" or header.startswith("mcp_servers.")):
        return False
    if header == "compat.claude" or header.startswith("compat.claude."):
        return False
    return True


def toml_str(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def toml_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return str(value)
    if isinstance(value, str):
        return toml_str(value)
    if isinstance(value, list):
        return "[ " + ", ".join(toml_value(v) for v in value) + " ]"
    raise TypeError(f"unsupported TOML value: {type(value).__name__}")


def emit_kv(key: str, value: object) -> str:
    return f"{key} = {toml_value(value)}\n"


def emit_inline_table(mapping: dict) -> str:
    parts = [f"{k} = {toml_value(v)}" for k, v in mapping.items()]
    return "{ " + ", ".join(parts) + " }"


def emit_mcp_tables(servers: dict, enabled: set[str]) -> str:
    chunks: list[str] = []
    for name, spec in servers.items():
        if not isinstance(spec, dict):
            continue
        lines = [f"[mcp_servers.{name}]\n"]
        stype = str(spec.get("type") or "").lower()
        url = spec.get("url")
        if stype in {"http", "sse", "streamable-http", "remote"} or url:
            if url:
                lines.append(emit_kv("url", url))
            headers = spec.get("headers")
            if isinstance(headers, dict) and headers:
                lines.append("headers = " + emit_inline_table(headers) + "\n")
        else:
            command = spec.get("command")
            if command:
                lines.append(emit_kv("command", command))
            args = spec.get("args")
            if isinstance(args, list) and args:
                lines.append(emit_kv("args", args))
            env = spec.get("env")
            if isinstance(env, dict) and env:
                lines.append("env = " + emit_inline_table(env) + "\n")
        lines.append(emit_kv("enabled", name in enabled))
        chunks.append("".join(lines))
    return "\n".join(chunks)


COMPAT_CLAUDE = """\
[compat.claude]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false
"""


def ensure_trailing_newline(text: str) -> str:
    return text if text.endswith("\n") or text == "" else text + "\n"


def merge(config_path: Path, mcp_path: Path | None, enabled_path: Path | None) -> None:
    original = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    preamble, tables = parse_tables(original)

    kept = [(h, aot, lines) for h, aot, lines in tables if keep_table(h, strip_mcp=mcp_path is not None)]
    out: list[str] = []
    out.extend(preamble)
    for _h, _aot, lines in kept:
        out.extend(lines)
    body = "".join(out)
    body = ensure_trailing_newline(body)
    if body and not body.endswith("\n\n"):
        body += "\n"

    extras: list[str] = [COMPAT_CLAUDE]
    if mcp_path is not None:
        servers = json.loads(mcp_path.read_text(encoding="utf-8"))
        enabled: set[str] = set()
        if enabled_path is not None:
            raw = json.loads(enabled_path.read_text(encoding="utf-8"))
            enabled = set(raw)
        mcp_block = emit_mcp_tables(servers, enabled)
        if mcp_block:
            extras.append(mcp_block)

    merged = body + "\n".join(ensure_trailing_newline(block) for block in extras)
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(ensure_trailing_newline(merged), encoding="utf-8")
    config_path.chmod(0o600)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config")
    parser.add_argument("--mcp", default=None)
    parser.add_argument("--enabled", default=None)
    args = parser.parse_args()

    mcp = Path(args.mcp) if args.mcp else None
    enabled = Path(args.enabled) if args.enabled else None
    if (mcp is None) ^ (enabled is None):
        print("merge-grok-mcp.py: --mcp and --enabled must be used together", file=sys.stderr)
        return 2
    merge(Path(args.config), mcp, enabled)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
