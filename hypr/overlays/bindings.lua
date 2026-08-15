-- Personal keybinding overrides. Omarchy defaults load first.
-- See current bindings: omarchy menu keybindings --print

local home = os.getenv("HOME") or ""

-- Browser profiles (stock SUPER+SHIFT+ALT+B is private mode).
hl.unbind("SUPER + SHIFT + B")
o.bind("SUPER + SHIFT + B", "Browser", 'omarchy-launch-browser --profile-directory="Default"')
hl.unbind("SUPER + SHIFT + ALT + B")
o.bind("SUPER + SHIFT + ALT + B", "Browser (Profile 1)", 'omarchy-launch-browser --profile-directory="Profile 1"')

o.bind("SUPER + SHIFT + K", "K9s", { tui = "k9s" })
o.bind("SUPER + SHIFT + V", "VMware Workstation", { focus = "^[Vv]mware$", launch = "vmware" })

-- Stock binds SUPER+/ to monitor scale cycling; passwords stay on SUPER+SHIFT+/.
hl.unbind("SUPER + SLASH")
hl.unbind("SUPER + ALT + SLASH")

-- Web apps. Unbind only where Quattro already claims the chord.
o.bind("SUPER + A", "Grok", 'omarchy-launch-webapp "https://grok.com" --profile-directory="Default"')
o.bind("SUPER + M", "Proton Mail", 'omarchy-launch-webapp "https://mail.proton.me/u/0/inbox" --profile-directory="Default"')
o.bind("SUPER + SHIFT + T", "Todoist", 'omarchy-launch-webapp "https://app.todoist.com/app/today" --profile-directory="Default"')
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Claude", 'omarchy-launch-webapp "https://claude.ai/chat" --profile-directory="Default"')
hl.unbind("SUPER + SHIFT + X")
o.bind("SUPER + SHIFT + X", "X", 'omarchy-launch-webapp "https://x.com/" --profile-directory="Default"')
hl.unbind("SUPER + SHIFT + Y")
o.bind("SUPER + SHIFT + Y", "YouTube", 'omarchy-launch-webapp "https://youtube.com/" --profile-directory="Profile 3"')
hl.unbind("SUPER + SHIFT + ALT + A")
o.bind("SUPER + SHIFT + ALT + A", "Athenis", 'omarchy-launch-webapp "https://app.athenis.io/" --profile-directory="Default"')
o.bind("SUPER + SHIFT + ALT + T", "Twitch", 'omarchy-launch-webapp "https://www.twitch.tv/" --profile-directory="Profile 3"')
o.bind("SUPER + SHIFT + ALT + K", "kick", 'omarchy-launch-webapp "https://www.kick.com/" --profile-directory="Profile 3"')
o.bind("SUPER + SHIFT + ALT + F", "Dropbox", 'omarchy-launch-webapp "https://www.dropbox.com/home" --profile-directory="Default"')
hl.unbind("SUPER + SHIFT + ALT + G")
o.bind("SUPER + SHIFT + ALT + G", "Grafana", 'omarchy-launch-webapp "https://cedeleon.grafana.net" --profile-directory="Default"')
o.bind("SUPER + SHIFT + ALT + H", "HomeAssistant", 'omarchy-launch-webapp "http://homeassistant.local:8123/config/" --profile-directory="Default"')
o.bind("SUPER + SHIFT + ALT + S", "Slack", 'omarchy-launch-webapp "https://app.slack.com/client/" --profile-directory="Profile 1"')
o.bind("SUPER + SHIFT + ALT + V", "TradingView", 'omarchy-launch-webapp "https://www.tradingview.com/chart/" --profile-directory="Default"')

-- Copilot key / SUPER+CTRL+X: push-to-talk (stock is menu + toggle).
hl.unbind("SUPER + SHIFT + code:201")
o.bind("SUPER + SHIFT + code:201", "Dictation (start)", "voxtype record start")
o.bind("SUPER + SHIFT + code:201", "Dictation (stop)", "voxtype record stop", { release = true })
hl.unbind("SUPER + CTRL + X")
o.bind("SUPER + CTRL + X", "Dictation (start)", "voxtype record start")
o.bind("SUPER + CTRL + X", "Dictation (stop)", "voxtype record stop", { release = true })
o.bind("SUPER + CTRL + SHIFT + X", "Dictation VM (start)", "voxtype record start --file=/run/user/1000/voxbridge.fifo")
o.bind("SUPER + CTRL + SHIFT + X", "Dictation VM (stop)", "voxtype record stop", { release = true })

o.bind("SUPER + CTRL + M", "Cycle monitor arrangement", home .. "/.config/hypr/monitor-setup.sh --swap")

-- Stock SUPER+CTRL+R is reminder-set; rescue stays on this chord.
hl.unbind("SUPER + CTRL + R")
o.bind("SUPER + CTRL + R", "Rescue displays (force on)", home .. "/.config/hypr/screen-rescue.sh", { locked = true })

-- Stock SUPER+CTRL+BACKSPACE squares a lone tiled window.
hl.unbind("SUPER + CTRL + BACKSPACE")
