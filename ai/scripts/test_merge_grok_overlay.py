"""Profile overlay must pin Bedrock on work machines without touching the seed."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "merge_grok_mcp",
    Path(__file__).with_name("merge-grok-mcp.py"),
)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("cannot load merge-grok-mcp.py")
_mod = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_mod)
apply_overlay = _mod.apply_overlay

SEED = """\
[cli]
auto_update = true

[models]
default = "grok-build"
web_search = "grok-4.20-multi-agent"

[ui]
theme = "tokyonight"
fork_secondary_model = "grok-build"

[subagents]
enabled = true
default_model = "grok-build"
"""

OVERLAY = """\
[models]
default = "us-gov.xai.grok-4.6"
web_search = "us-gov.xai.grok-4.6"
hidden_models = ["grok-4.6", "grok-4.5"]
session_summary = "us-gov.xai.grok-4.6"
max_retries = 2

[ui]
fork_secondary_model = "us-gov.xai.grok-4.6"

[subagents]
default_model = "us-gov.xai.grok-4.6"

[model."us-gov.xai.grok-4.6"]
model = "us-gov.xai.grok-4.6"
base_url = "http://127.0.0.1:18787/openai/v1"
name = "GovCloud Grok 4.6"
api_backend = "responses"
env_key = "GROK_BEDROCK_API_KEY"
context_window = 500000
"""


class OverlayMergeTests(unittest.TestCase):
    def test_pins_bedrock_and_keeps_personal_ui(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.toml"
            overlay = Path(tmp) / "overlay.toml"
            config.write_text(SEED, encoding="utf-8")
            overlay.write_text(OVERLAY, encoding="utf-8")
            apply_overlay(config, overlay)
            text = config.read_text(encoding="utf-8")

        self.assertIn('default = "us-gov.xai.grok-4.6"', text)
        self.assertNotIn('default = "grok-build"', text)
        self.assertIn('theme = "tokyonight"', text)
        self.assertIn('fork_secondary_model = "us-gov.xai.grok-4.6"', text)
        self.assertIn("[model.\"us-gov.xai.grok-4.6\"]", text)
        self.assertIn('name = "GovCloud Grok 4.6"', text)
        self.assertIn("enabled = true", text)

    def test_reapply_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.toml"
            overlay = Path(tmp) / "overlay.toml"
            config.write_text(SEED, encoding="utf-8")
            overlay.write_text(OVERLAY, encoding="utf-8")
            apply_overlay(config, overlay)
            apply_overlay(config, overlay)
            text = config.read_text(encoding="utf-8")

        self.assertEqual(text.count("[model.\"us-gov.xai.grok-4.6\"]"), 1)
        self.assertEqual(text.count('default = "us-gov.xai.grok-4.6"'), 1)

    def test_replaces_existing_model_table(self) -> None:
        live = SEED + """
[model."us-gov.xai.grok-4.6"]
name = "old"
"""
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.toml"
            overlay = Path(tmp) / "overlay.toml"
            config.write_text(live, encoding="utf-8")
            overlay.write_text(OVERLAY, encoding="utf-8")
            apply_overlay(config, overlay)
            text = config.read_text(encoding="utf-8")

        self.assertIn('name = "GovCloud Grok 4.6"', text)
        self.assertNotIn('name = "old"', text)


if __name__ == "__main__":
    unittest.main()
