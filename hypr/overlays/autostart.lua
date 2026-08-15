-- Extra autostart processes.

local home = os.getenv("HOME") or ""

o.exec_on_start(home .. "/.config/hypr/monitor-listener.sh")
o.exec_on_start(home .. "/.config/hypr/monitor-setup.sh --startup")
