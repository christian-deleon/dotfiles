-- Personal look'n'feel overrides. Omarchy defaults load first.

hl.env("OMARCHY_SCREENSHOT_DIR", (os.getenv("HOME") or "") .. "/Pictures/screenshots")

-- Hybrid: displays/compositor are Intel. Omarchy 4.0.1 sets
-- LIBVA_DRIVER_NAME=nvidia whenever a GSP NVIDIA GPU is present,
-- so Chromium NVDEC-decodes then DMA-BUF-imports into Intel GL.
-- https://github.com/basecamp/omarchy/issues/8215
hl.env("LIBVA_DRIVER_NAME", "iHD")

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
