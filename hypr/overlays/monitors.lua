-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- Desk OLEDs share a description and no serial; connector names shuffle
-- behind the dock MST chain. These rules set mode/scale; monitor-setup.sh
-- pins left-to-right order from the persisted port map.

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- ThinkPad T1g Gen 8 — Samsung OLED 3200x2000 120Hz
hl.monitor({
  output = "eDP-1",
  mode = "3200x2000@120",
  position = "auto",
  scale = 1.33,
  bitdepth = 10,
  cm = "hdr",
})

-- Triple MSI MAG 321UP OLED
hl.monitor({
  output = "desc:Microstep MAG321UP OLED",
  mode = "3840x2160@120",
  position = "auto",
  scale = 1,
  bitdepth = 10,
})

-- Portable ViewSonic VX1655-OLED
hl.monitor({
  output = "desc:ViewSonic Corporation VX1655-OLED",
  mode = "3840x2160@60",
  position = "auto",
  scale = 1.5,
})

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
