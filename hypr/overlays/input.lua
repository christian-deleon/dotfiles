-- Personal input overrides. Omarchy defaults load first.

hl.config({
  input = {
    repeat_delay = 600,
  },
})

hl.device({
  name = "tpps/2-elan-trackpoint",
  sensitivity = 0.5,
  accel_profile = "flat",
})

hl.device({
  name = "glorious-model-d-2-pro",
  sensitivity = 0,
  accel_profile = "flat",
})

-- VMware (XWayland) doesn't release keys it already passed to the guest when it
-- loses focus. Leaving it with a SUPER chord (SUPER+2, the launcher, ...) leaves
-- Win held in Windows, and typing fires Win+letter shortcuts. Release Win each
-- time VMware regains focus. Ctrl stays down around the Win taps so Windows
-- doesn't treat them as a bare Win press and open Start.
local VMWARE_WIN_RELEASE = {
  { "Control_L", "down" },
  -- Xwayland drops a press of a modifier it already holds and a release of one
  -- it doesn't, so up/down/up delivers a release either way.
  { "Super_L", "up" }, { "Super_L", "down" }, { "Super_L", "up" },
  { "Super_R", "up" }, { "Super_R", "down" }, { "Super_R", "up" },
  { "Control_L", "up" },
}

local function is_vmware(window)
  return window ~= nil and (window.class or ""):lower() == "vmware"
end

hl.on("window.active", function(window)
  if not is_vmware(window) then
    return
  end
  -- Xwayland takes X focus over a separate connection; keys sent in the same
  -- tick can land before VMware has it.
  hl.timer(function()
    if not is_vmware(hl.get_active_window()) then
      return
    end
    for _, step in ipairs(VMWARE_WIN_RELEASE) do
      hl.dispatch(hl.dsp.send_key_state({ mods = "", key = step[1], state = step[2] }))
    end
  end, { timeout = 100, type = "oneshot" })
end)
