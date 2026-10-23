-- Workday layout, rebuilt on demand (see bindings.lua). Pressing the bind
-- again after rearranging restores it; missing apps are launched and slotted
-- in as their windows map.
--
--   left monitor, workspace 6         middle monitor, workspace 7
--   ┌──────────────────┬───────┐      ┌──────────────────────────┐
--   │                  │ Slack │      │                          │
--   │  Work browser    │       │      │  VMware (fullscreen)     │
--   │                  ├───────┤      │                          │
--   │                  │ Files │      │                          │
--   └──────────────────┴───────┘      └──────────────────────────┘

local M = {}

local DESK = "6"
local VM = "7"
local STASH = "special:worklayout"
local MSI_DESC = "Microstep MAG321UP OLED"
-- dwindle splitratio: 1.0 is 50/50, so 1.5 gives the first child 75%.
local RATIO = "1.5"
-- Stop claiming new windows for launched apps after this long.
local PENDING_MS = 60000

-- Chromium profiles share one class and their titles omit the profile, so the
-- work browser is the window this module launched, else any Chromium on DESK.
-- Nautilus is handled the same way so personal file windows stay put.
local APPS = {
  browser = {
    class = "chromium",
    on_desk_only = true,
    launch = o.launch('chromium --new-window --profile-directory="Profile 1"'),
  },
  slack = { class = "slack", launch = o.launch("slack") },
  files = {
    class = "org.gnome.Nautilus",
    on_desk_only = true,
    launch = o.launch("nautilus --new-window"),
  },
  vmware = {
    class = "Vmware",
    -- Skip VMware's dialogs, which share the class.
    title = "VMware Workstation$",
    launch = o.launch("env GDK_SCALE=1 GDK_DPI_SCALE=1 vmware"),
  },
}

-- Browser | (Slack over Files).
local DESK_ORDER = { "browser", "slack", "files" }

local claimed = {}
local pending = {}
local pending_timer
local arrange_queued = false

local function sel(window)
  return "address:" .. window.address
end

local function dispatch(dsp)
  hl.dispatch(dsp)
end

local function matches(app, window)
  return window.mapped
    and window.class == app.class
    and (not app.title or (window.title or ""):find(app.title) ~= nil)
end

local function find(role)
  local app = APPS[role]
  if claimed[role] then
    local window = hl.get_window("address:" .. claimed[role])
    if window and matches(app, window) then
      return window
    end
    claimed[role] = nil
  end

  local fallback
  for _, window in ipairs(hl.get_windows({ class = app.class })) do
    if matches(app, window) then
      local ws = window.workspace and window.workspace.name
      if ws == DESK or (role == "vmware" and ws == VM) then
        return window
      end
      fallback = fallback or window
    end
  end
  if not app.on_desk_only then
    return fallback
  end
end

local function settle(window)
  if window.fullscreen ~= 0 then
    dispatch(hl.dsp.window.fullscreen({ window = sel(window), action = "unset" }))
  end
  if window.floating then
    dispatch(hl.dsp.window.float({ window = sel(window), action = "off" }))
  end
end

local function move(window, workspace)
  dispatch(hl.dsp.window.move({ window = sel(window), workspace = workspace, follow = false }))
end

local function focus(window)
  dispatch(hl.dsp.focus({ window = sel(window) }))
end

-- Dwindle builds its tree from insertion order, so rebuild from an empty
-- workspace instead of trying to repair whatever the tree became.
local function arrange_desk()
  local tiles, is_tile = {}, {}
  for _, role in ipairs(DESK_ORDER) do
    local window = find(role)
    if window then
      tiles[#tiles + 1] = window
      is_tile[window.address] = true
    end
  end

  local extras = {}
  for _, window in ipairs(hl.get_workspace_windows(DESK)) do
    if not is_tile[window.address] then
      extras[#extras + 1] = window
    end
    settle(window)
    move(window, STASH)
  end

  -- Second tile splits right of the first, third splits below the second.
  local splits = { nil, "r", "d" }
  for i, window in ipairs(tiles) do
    settle(window)
    if i > 1 then
      focus(tiles[i - 1])
      dispatch(hl.dsp.layout("preselect " .. splits[i]))
    end
    move(window, DESK)
  end

  if #tiles >= 2 then
    focus(tiles[1])
    dispatch(hl.dsp.layout("splitratio " .. RATIO .. " exact"))
  end
  if #tiles == 3 then
    focus(tiles[2])
    dispatch(hl.dsp.layout("splitratio " .. RATIO .. " exact"))
  end

  -- Unrelated windows go back on the desk; they split the focused tile.
  for _, window in ipairs(extras) do
    move(window, DESK)
  end

  return tiles[1]
end

local function arrange_vm()
  local window = find("vmware")
  if not window then
    return
  end
  if not (window.workspace and window.workspace.name == VM) then
    settle(window)
    move(window, VM)
  end
  dispatch(hl.dsp.window.fullscreen({ window = sel(window), mode = "fullscreen", action = "set" }))
  return window
end

-- The desk OLEDs have shuffling connector names; monitor-setup.sh pins their
-- left-to-right order, so place by position instead of by name.
local function place_workspaces()
  local desk = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if (monitor.description or ""):find(MSI_DESC, 1, true) == 1 then
      desk[#desk + 1] = monitor
    end
  end
  if #desk < 2 then
    return
  end
  table.sort(desk, function(a, b)
    return a.x < b.x
  end)

  for workspace, monitor in pairs({ [DESK] = desk[1], [VM] = desk[2] }) do
    if hl.get_workspace(workspace) then
      dispatch(hl.dsp.workspace.move({ workspace = workspace, monitor = monitor.name }))
    end
  end
end

local function arrange()
  local vm = arrange_vm()
  local browser = arrange_desk()
  place_workspaces()

  -- Focusing a window shows its workspace on its monitor.
  if vm then
    focus(vm)
  end
  if browser then
    focus(browser)
  end
end

local function queue_arrange()
  if arrange_queued then
    return
  end
  arrange_queued = true
  -- Let the new window finish mapping (title, size) before rebuilding.
  hl.timer(function()
    arrange_queued = false
    arrange()
  end, { timeout = 500, type = "oneshot" })
end

local function claim(window)
  if not (window and window.mapped) then
    return
  end
  for role in pairs(pending) do
    if matches(APPS[role], window) then
      pending[role] = nil
      claimed[role] = window.address
      queue_arrange()
      return
    end
  end
end

hl.on("window.open", claim)
-- Some apps (XWayland) map before their class or title is final.
hl.on("window.class", claim)
hl.on("window.title", claim)

function M.apply()
  for role, app in pairs(APPS) do
    if not pending[role] and not find(role) then
      pending[role] = true
      hl.exec_cmd(app.launch)
    end
  end

  if next(pending) then
    if pending_timer then
      pending_timer:set_enabled(false)
    end
    pending_timer = hl.timer(function()
      pending = {}
    end, { timeout = PENDING_MS, type = "oneshot" })
  end

  arrange()
end

return M
