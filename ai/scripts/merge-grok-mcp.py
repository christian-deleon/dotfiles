#!/usr/bin/env python3
# Merge MCP servers into live ~/.grok/config.toml and force Claude compat off.
# Optional --overlay upserts a profile overlay (model tables + selected keys).
#
# Usage:
#   merge-grok-mcp.py <config.toml>
#   merge-grok-mcp.py <config.toml> --mcp <resolved.json> --enabled <enabled.json>
#   merge-grok-mcp.py <config.toml> --overlay <profile.toml>
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
ENABLED_TRUE_RE = re.compile(r"^enabled\s*=\s*true\b")


def parse_tables(
    text: str,
) -> tuple[list[str], list[tuple[str | None, bool, list[str]]]]:
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


def live_enabled_servers(
    tables: list[tuple[str | None, bool, list[str]]],
) -> set[str]:
    """Servers already enabled in live Grok config ([mcp_servers.name], not .env)."""
    enabled: set[str] = set()
    for header, _aot, lines in tables:
        if header is None or not header.startswith("mcp_servers."):
            continue
        name = header.removeprefix("mcp_servers.")
        if "." in name:
            continue
        if any(ENABLED_TRUE_RE.match(line.strip()) for line in lines):
            enabled.add(name)
    return enabled


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


KV_RE = re.compile(r"^([A-Za-z0-9_]+)\s*=")


def _overlay_kvs(lines: list[str]) -> dict[str, str]:
    kvs: dict[str, str] = {}
    for line in lines[1:]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        m = KV_RE.match(stripped)
        if m:
            kvs[m.group(1)] = line if line.endswith("\n") else line + "\n"
    return kvs


def _upsert_table(live_lines: list[str], overlay_lines: list[str]) -> list[str]:
    kvs = _overlay_kvs(overlay_lines)
    seen: set[str] = set()
    out: list[str] = [live_lines[0]]
    for line in live_lines[1:]:
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            m = KV_RE.match(stripped)
            if m and m.group(1) in kvs:
                if m.group(1) not in seen:
                    out.append(kvs[m.group(1)])
                    seen.add(m.group(1))
                continue
        out.append(line)
    missing = [kvs[k] for k in kvs if k not in seen]
    if missing:
        trail: list[str] = []
        while out and out[-1].strip() == "":
            trail.append(out.pop())
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        out.extend(missing)
        out.extend(reversed(trail))
    return out


def apply_overlay(config_path: Path, overlay_path: Path) -> None:
    """Upsert overlay tables into live config. model.* tables are replaced whole."""
    original = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    overlay_text = overlay_path.read_text(encoding="utf-8")
    preamble, live_tables = parse_tables(original)
    _, overlay_tables = parse_tables(overlay_text)

    replace_headers = {
        h for h, _aot, _lines in overlay_tables if h is not None and h.startswith("model.")
    }
    overlay_by_header = {h: lines for h, _aot, lines in overlay_tables if h is not None}

    kept: list[tuple[str | None, bool, list[str]]] = []
    seen_headers: set[str] = set()
    for header, aot, lines in live_tables:
        if header in replace_headers:
            continue
        if header in overlay_by_header and not (header or "").startswith("model."):
            kept.append((header, aot, _upsert_table(lines, overlay_by_header[header])))
            seen_headers.add(header)
        else:
            kept.append((header, aot, lines))
            if header is not None:
                seen_headers.add(header)

    extras: list[list[str]] = []
    for header, _aot, lines in overlay_tables:
        if header is None:
            continue
        if header.startswith("model.") or header not in seen_headers:
            extras.append(lines)

    out: list[str] = []
    out.extend(preamble)
    for _h, _aot, lines in kept:
        out.extend(lines)
    body = ensure_trailing_newline("".join(out))
    if extras:
        if body and not body.endswith("\n\n"):
            body += "\n"
        body += "".join(
            ensure_trailing_newline("".join(lines)) for lines in extras
        )
        if not body.endswith("\n"):
            body += "\n"

    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(ensure_trailing_newline(body), encoding="utf-8")
    config_path.chmod(0o600)


def merge(config_path: Path, mcp_path: Path | None, enabled_path: Path | None) -> None:
    original = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    preamble, tables = parse_tables(original)
    preserved_enabled = live_enabled_servers(tables)

    kept = [
        (h, aot, lines)
        for h, aot, lines in tables
        if keep_table(h, strip_mcp=mcp_path is not None)
    ]
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
        enabled |= preserved_enabled
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
    parser.add_argument("--overlay", default=None)
    args = parser.parse_args()

    mcp = Path(args.mcp) if args.mcp else None
    enabled = Path(args.enabled) if args.enabled else None
    if (mcp is None) ^ (enabled is None):
        print(
            "merge-grok-mcp.py: --mcp and --enabled must be used together",
            file=sys.stderr,
        )
        return 2
    merge(Path(args.config), mcp, enabled)
    if args.overlay:
        apply_overlay(Path(args.config), Path(args.overlay))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
