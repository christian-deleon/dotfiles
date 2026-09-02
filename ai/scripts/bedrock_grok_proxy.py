#!/usr/bin/env python3
"""Proxy Bedrock OpenAI-compat traffic and drop GovCloud's trailing fake SSE error.

GovCloud bedrock-runtime appends this after response.completed / incomplete
(and after chat finish_reason):

    data: {"error":{"type":"server_error","code":"internal_server_error",...}}
    data: [DONE]

Grok Build treats that as a failed turn even when the model already streamed
text. This proxy forwards to Bedrock and strips that glitch when a terminal
event already arrived. A stream that is *only* that error is left intact.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

UPSTREAM = "https://bedrock-runtime.us-gov-west-1.amazonaws.com"
HOP_BY_HOP = frozenset(
    {
        "connection",
        "content-length",
        "host",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
    }
)


def _payloads(block: str) -> list[object]:
    out: list[object] = []
    for line in block.splitlines():
        if not line.startswith("data:"):
            continue
        raw = line[5:].strip()
        if raw == "[DONE]" or not raw:
            continue
        try:
            out.append(json.loads(raw))
        except json.JSONDecodeError:
            continue
    return out


def _is_glitch(block: str) -> bool:
    for payload in _payloads(block):
        if not isinstance(payload, dict):
            continue
        err = payload.get("error")
        if not isinstance(err, dict):
            continue
        if err.get("type") == "server_error" and err.get("code") == "internal_server_error":
            return True
    return False


def _is_terminal(block: str) -> bool:
    for payload in _payloads(block):
        if not isinstance(payload, dict):
            continue
        if payload.get("type") in {"response.completed", "response.incomplete"}:
            return True
        for choice in payload.get("choices") or []:
            if isinstance(choice, dict) and choice.get("finish_reason"):
                return True
    return False


def filter_sse(text: str) -> str:
    seen_terminal = False
    out: list[str] = []
    buf: list[str] = []

    def flush(block: str) -> None:
        nonlocal seen_terminal
        if not block:
            return
        if _is_glitch(block) and seen_terminal:
            return
        if _is_terminal(block):
            seen_terminal = True
        out.append(block)

    for line in text.splitlines(keepends=True):
        buf.append(line)
        if line in ("\n", "\r\n"):
            flush("".join(buf))
            buf = []
    flush("".join(buf))
    return "".join(out)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _forward(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else None
        headers = {
            k: v
            for k, v in self.headers.items()
            if k.lower() not in HOP_BY_HOP
        }
        url = UPSTREAM + self.path
        req = urllib.request.Request(url, data=body, headers=headers, method=self.command)
        try:
            upstream = urllib.request.urlopen(req, timeout=600)
        except urllib.error.HTTPError as exc:
            raw = exc.read()
            self.send_response(exc.code)
            ctype = exc.headers.get("Content-Type", "application/json") if exc.headers else "application/json"
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return

        raw = upstream.read()
        ctype = upstream.headers.get("Content-Type", "application/json")
        if raw.lstrip().startswith(b"data:"):
            raw = filter_sse(raw.decode("utf-8", "replace")).encode()
        self.send_response(upstream.status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    do_GET = _forward
    do_POST = _forward
    do_PUT = _forward
    do_DELETE = _forward


def _already_listening(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def _daemonize() -> None:
    if os.fork() != 0:
        raise SystemExit(0)
    os.setsid()
    if os.fork() != 0:
        raise SystemExit(0)
    os.chdir("/")
    sys.stdin.close()
    log_dir = os.path.expanduser("~/.grok/logs")
    os.makedirs(log_dir, exist_ok=True)
    log = open(os.path.join(log_dir, "bedrock-grok-proxy.log"), "ab", buffering=0)
    os.dup2(log.fileno(), 1)
    os.dup2(log.fileno(), 2)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18787)
    parser.add_argument("--daemon", action="store_true")
    args = parser.parse_args()
    if _already_listening(args.port):
        return 0
    if args.daemon:
        _daemonize()
        if _already_listening(args.port):
            return 0
    httpd = HTTPServer(("127.0.0.1", args.port), Handler)
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
