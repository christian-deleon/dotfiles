-- One shared set of workspaces 1-10 across all monitors, as before Omarchy 4.5,
-- instead of 4.5's per-monitor blocks (1-10, 11-20, ... per monitor).
--
-- Overrides internals of /usr/share/omarchy/default/hypr/monitor-workspaces.lua,
-- so recheck after Omarchy updates. To go back to per-monitor workspaces,
-- drop the require in bindings.lua and rename the block file's .bak back.

local W = o.workspaces
if not W then
  return
end

-- Omarchy renumbers workspaces into monitor blocks on start, reload and
-- hotplug, always through this table field.
function W.reconcile() end

-- The bar places and labels workspaces by each monitor's block in this file.
-- With no entry for a monitor it uses the block of the workspace that monitor
-- shows, which is the first block once ids stay in 1-10. Nothing rewrites the
-- file while reconcile is off.
local blocks = require("default.hypr.paths").state_home .. "/omarchy/monitor-workspaces"
os.rename(blocks, blocks .. ".bak")

local function action(fn, expression)
  o.bind_expressions[fn] = expression
  return fn
end

-- Global ids for the bar's clicks, the keybindings menu, and the rebinds below.
-- The bar passes a monitor name as a second argument; a global id needs none.
function W.focus(id)
  return action(function()
    hl.dispatch(hl.dsp.focus({ workspace = tostring(id) }))
  end, "o.workspaces.focus(" .. id .. ")")
end

function W.move_window(id, follow)
  return action(function()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = follow ~= false }))
  end, "o.workspaces.move_window(" .. id .. (follow == false and ", false" or "") .. ")")
end

function W.move_to_monitor(direction)
  return action(function()
    hl.dispatch(hl.dsp.workspace.move({ monitor = direction }))
  end, string.format("o.workspaces.move_to_monitor(%q)", direction))
end

-- Omarchy bound these to its per-monitor versions before this file loads.
for n = 1, 10 do
  local key = "code:" .. (n + 9)
  o.rebind("SUPER + " .. key, "Switch to workspace " .. n, W.focus(n))
  o.rebind("SUPER + SHIFT + " .. key, "Move window to workspace " .. n, W.move_window(n))
  o.rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. n, W.move_window(n, false))
end

o.rebind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
o.rebind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
o.rebind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))
o.rebind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "e+1" }))
o.rebind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "e-1" }))

o.rebind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", W.move_to_monitor("l"))
o.rebind("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", W.move_to_monitor("r"))
o.rebind("SUPER + SHIFT + ALT + UP", "Move workspace to up monitor", W.move_to_monitor("u"))
o.rebind("SUPER + SHIFT + ALT + DOWN", "Move workspace to down monitor", W.move_to_monitor("d"))
