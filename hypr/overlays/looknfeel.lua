-- Personal look'n'feel overrides. Omarchy defaults load first.

hl.env("OMARCHY_SCREENSHOT_DIR", (os.getenv("HOME") or "") .. "/Pictures/screenshots")

hl.config({
  general = {
    gaps_in = 3,
    gaps_out = 3,
  },
  misc = {
    -- Keep toasts/bells; don't steal focus when a window requests activation.
    focus_on_activate = false,
  },
})

-- Slightly less transparency than the default-opacity tag (0.985 / 0.96).
o.window({ tag = "default-opacity" }, { opacity = "1.0 0.97" })

-- Agent Chromium: float overlay on the current workspace (do not pin).
o.window("^chromium-agent$", {
  float = true,
  size = { 1300, 1500 },
  center = true,
  tag = "+pop",
})
