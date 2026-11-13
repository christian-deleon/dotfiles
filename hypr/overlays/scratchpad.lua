-- Scratchpad apps launch at login and tile into fixed slots by window class,
-- so the order they open in never changes the arrangement:
--
--   ┌───────────────┬───────────────┐
--   │               │    Spotify    │
--   │  Proton Mail  ├───────┬───────┤
--   ├───────┬───────┤ Grok  │ Blue- │
--   │Todoist│Obsidi.│ Bot   │Bubbles│
--   └───────┴───────┴───────┴───────┘

local home = os.getenv("HOME") or ""

local SCRATCHPAD = "special:scratchpad"
-- Only windows opened this soon after login are sent to the scratchpad.
local ROUTE_WINDOW_S = 120
-- A config reload re-runs this file in a fresh Lua state but never fires
-- hyprland.start again, and Omarchy's monitor watcher reloads at login while
-- dock displays are still modeless. The deadline lives in the compositor
-- environment, which survives reloads, tagged with this session's signature.
local DEADLINE_ENV = "DOT_SCRATCHPAD_ROUTE_UNTIL"
local SESSION = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""

local APPS = {
  mail = {
    class = "chrome-mail.proton.me__u_0_inbox-Default",
    launch = 'omarchy-launch-webapp "https://mail.proton.me/u/0/inbox" --profile-directory=Default',
  },
  todoist = {
    class = "chrome-app.todoist.com__app_today-Default",
    launch = 'omarchy-launch-webapp "https://app.todoist.com/app/today" --profile-directory=Default',
  },
  spotify = { class = "Spotify", launch = o.launch("spotify") },
  obsidian = { class = "md.obsidian.Obsidian", launch = o.launch("obsidian") },
  grok = { class = "grok-bot", launch = o.launch(home .. "/.local/share/grok-bot/appimage") },
  bluebubbles = { class = "bluebubbles", launch = o.launch("bluebubbles") },
}

-- A split gives `ratio` of its box to the first child, on `side`. When every
-- app under one child is closed, the other child takes the whole box.
local TREE = {
  side = "left", ratio = 0.5,
  { side = "top", ratio = 0.634, "mail", { side = "left", ratio = 0.5, "todoist", "obsidian" } },
  { side = "top", ratio = 0.5, "spotify", { side = "left", ratio = 0.5, "grok", "bluebubbles" } },
}

local OPPOSITE = { left = "right", right = "left", top = "bottom", bottom = "top" }

local slot_of = {}
for slot, app in pairs(APPS) do
  slot_of[app.class] = slot
end

local function occupied(node, targets)
  if type(node) == "string" then
    return targets[node] ~= nil
  end
  return occupied(node[1], targets) or occupied(node[2], targets)
end

local function place(ctx, node, box, targets)
  if type(node) == "string" then
    targets[node]:place(box)
    return
  end

  local first, second = occupied(node[1], targets), occupied(node[2], targets)
  if first and second then
    place(ctx, node[1], ctx:split(box, node.side, node.ratio), targets)
    place(ctx, node[2], ctx:split(box, OPPOSITE[node.side], 1 - node.ratio), targets)
  elseif first then
    place(ctx, node[1], box, targets)
  elseif second then
    place(ctx, node[2], box, targets)
  end
end

hl.layout.register("scratchpad", {
  recalculate = function(ctx)
    local targets, stray = {}, false
    for _, target in ipairs(ctx.targets) do
      local slot = target.window and slot_of[target.window.class]
      if slot and not targets[slot] then
        targets[slot] = target
      else
        stray = true
      end
    end

    -- An extra or duplicate window has no slot; a grid keeps every window visible.
    if stray then
      local cols = math.ceil(math.sqrt(#ctx.targets))
      for i, target in ipairs(ctx.targets) do
        target:place(ctx:grid_cell(i, cols))
      end
      return
    end

    place(ctx, TREE, ctx.area, targets)
  end,
})

hl.workspace_rule({ workspace = SCRATCHPAD, layout = "lua:scratchpad" })

local function routing()
  local owner, deadline = (os.getenv(DEADLINE_ENV) or ""):match("^(.*):(%d+)$")
  return owner == SESSION and os.time() < tonumber(deadline)
end

-- slot -> address of the window routed into it. Only one window per app is
-- routed; a second copy (e.g. two launchers racing) would push the layout
-- into its grid fallback. Seeded from the scratchpad so a reload keeps it.
local routed = {}
for _, window in ipairs(hl.get_workspace_windows(SCRATCHPAD) or {}) do
  local slot = slot_of[window.class]
  if slot and not routed[slot] then
    routed[slot] = window.address
  end
end

-- Spotify (XWayland) can map before its class is set, so also route on class
-- change. window.class also fires before a window maps; skip that one and let
-- window.open route it.
local function route(window)
  local slot = window and window.mapped and slot_of[window.class]
  if not slot or routed[slot] or not routing() then
    return
  end
  routed[slot] = window.address
  if not (window.workspace and window.workspace.name == SCRATCHPAD) then
    hl.dispatch(hl.dsp.window.move({ workspace = SCRATCHPAD, follow = false, window = window }))
  end
end

-- Free the slot if its window closes during login, so a replacement still routes.
local function release(window)
  local slot = window and slot_of[window.class]
  if slot and routed[slot] == window.address then
    routed[slot] = nil
  end
end

hl.on("window.open", route)
hl.on("window.class", route)
hl.on("window.close", release)

hl.on("hyprland.start", function()
  hl.env(DEADLINE_ENV, SESSION .. ":" .. (os.time() + ROUTE_WINDOW_S))

  for _, app in pairs(APPS) do
    hl.exec_cmd(app.launch)
  end
end)
