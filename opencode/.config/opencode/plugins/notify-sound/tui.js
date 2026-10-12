import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { Plugin } from "@opencode/plugin/tui"

const HOOK = `${homedir()}/.dotfiles/ai/hooks/stop_notify.sh`

// Runs in the TUI process, not the shared background service, so the hook
// inherits this terminal's TMUX_PANE. Every TUI receives every session's
// events, so only notify for root sessions this TUI is showing; subagents
// going idle mid-turn are not "turn complete".
function shownHere(context, sessionID) {
  const route = context.ui.router.current()
  if (route.type === "session" && context.data.session.root(route.sessionID) === sessionID) return true
  return context.ui.tabs.enabled() && context.ui.tabs.list().some((tab) => tab.sessionID === sessionID)
}

export default Plugin.define({
  id: "dotfiles.notify-sound",
  setup(context) {
    return context.data.on("session.idle", (event) => {
      const { sessionID } = event.data
      if (context.data.session.root(sessionID) !== sessionID) return
      if (!shownHere(context, sessionID)) return
      const cwd = event.location?.directory ?? process.cwd()
      const hook = spawn(HOOK, [], { stdio: ["pipe", "ignore", "ignore"] })
      hook.on("error", () => {})
      hook.stdin.end(JSON.stringify({ cwd }))
    })
  },
})
