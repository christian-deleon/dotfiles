"""Grok config merge keeps folder trust off."""

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
_merge_mod = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_merge_mod)
merge = _merge_mod.merge


class FolderTrustOffTests(unittest.TestCase):
    # Grok docs (10-hooks.md): disable with `[folder_trust] enabled = false`.
    # New git worktrees are separate workspaces, so a parent grant does not
    # skip the blocking "Do you trust this directory?" modal.
    def test_merge_forces_folder_trust_off(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.toml"
            config.write_text("[cli]\nauto_update = true\n", encoding="utf-8")
            merge(config, None, None)
            text = config.read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^\[folder_trust\]\nenabled = false\n")

    def test_merge_replaces_existing_folder_trust_on(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.toml"
            config.write_text(
                "[cli]\nauto_update = true\n\n"
                "[folder_trust]\nenabled = true\n",
                encoding="utf-8",
            )
            merge(config, None, None)
            text = config.read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^\[folder_trust\]\nenabled = false\n")
        self.assertNotRegex(text, r"(?m)^enabled = true\n")
        self.assertEqual(text.count("[folder_trust]"), 1)


if __name__ == "__main__":
    unittest.main()
