"""Regen must not disable MCP servers the user already turned on."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "merge_grok_mcp",
    Path(__file__).with_name("merge-grok-mcp.py"),
)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("cannot load merge-grok-mcp.py")
_merge_mod = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_merge_mod)
merge = _merge_mod.merge


LIVE = """\
[cli]
auto_update = true

[mcp_servers.context7]
command = "npx"
enabled = true

[mcp_servers.aws]
command = "uvx"
enabled = true

[mcp_servers.grafana]
command = "uvx"
enabled = true

[mcp_servers.docker]
command = "uvx"
enabled = false
"""

MCP = {
    "context7": {"command": "npx", "args": ["-y", "x"]},
    "aws": {
        "command": "python3",
        "args": ["shim.py", "uvx", "mcp-proxy-for-aws@1.6.4"],
    },
    "grafana": {"command": "uvx", "args": ["mcp-grafana"]},
    "docker": {"command": "uvx", "args": ["mcp-server-docker"]},
}


class PreserveEnabledTests(unittest.TestCase):
    def test_union_defaults_with_already_enabled_servers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = root / "config.toml"
            config.write_text(LIVE, encoding="utf-8")
            mcp_path = root / "mcp.json"
            mcp_path.write_text(json.dumps(MCP), encoding="utf-8")
            enabled_path = root / "enabled.json"
            enabled_path.write_text(
                json.dumps(["context7", "firecrawl"]), encoding="utf-8"
            )

            merge(config, mcp_path, enabled_path)
            text = config.read_text(encoding="utf-8")

        self.assertIn('command = "python3"', text)
        self.assertRegex(text, r"\[mcp_servers\.aws\][\s\S]*?enabled = true")
        self.assertRegex(text, r"\[mcp_servers\.grafana\][\s\S]*?enabled = true")
        self.assertRegex(text, r"\[mcp_servers\.docker\][\s\S]*?enabled = false")
        self.assertRegex(text, r"\[mcp_servers\.context7\][\s\S]*?enabled = true")


if __name__ == "__main__":
    unittest.main()
