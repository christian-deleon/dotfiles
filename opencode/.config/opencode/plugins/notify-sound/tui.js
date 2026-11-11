import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { Plugin } from "@opencode/plugin/tui"

const HOOKS = `${homedir()}/.dotfiles/ai/hooks`

// Runs in the TUI process, not the shared background service, so the hooks
// inherit this terminal's TMUX_PANE. Every TUI receives every session's
// events, so only act for sessions this TUI is showing. The TUI never
// receives session.idle in OpenCode 2.2; a turn ends with
// session.execution.succeeded / failed / interrupted.
function shownHere(context, sessionID) {
  const route = context.ui.router.current()
  if (route.type === "session" && context.data.session.root(route.sessionID) === sessionID) return true
  return context.ui.tabs.enabled() && context.ui.tabs.list().some((tab) => tab.sessionID === sessionID)
}

function run(script, args, payload) {
  const child = spawn(`${HOOKS}/${script}`, args, { stdio: ["pipe", "ignore", "ignore"] })
  child.on("error", () => {})
  child.stdin.end(JSON.stringify(payload))
}

export default Plugin.define({
  id: "dotfiles.notify-sound",
  setup(context) {
    // onlyRoot: a subagent's turn starting or ending is not the session's.
    // A permission prompt or question in a subagent still waits on the user.
    const on = (type, onlyRoot, act) =>
      context.data.on(type, (event) => {
        const sessionID = event.data.sessionID ?? event.data.form?.sessionID
        if (!sessionID) return
        const root = context.data.session.root(sessionID)
        if (onlyRoot && root !== sessionID) return
        if (!shownHere(context, root)) return
        act(event)
      })
    const state = (value) => () => run("session_state.sh", [value], {})
    const turnEnded = (event) => {
      run("session_state.sh", ["idle"], {})
      run("stop_notify.sh", [], { cwd: event.location?.directory ?? process.cwd() })
    }

    const offs = [
      on("session.execution.started", true, state("working")),
      on("session.execution.succeeded", true, turnEnded),
      on("session.execution.failed", true, turnEnded),
      on("session.execution.interrupted", true, state("idle")),
      on("permission.asked", false, state("blocked")),
      on("form.created", false, state("blocked")),
      on("permission.replied", false, state("working")),
      on("form.replied", false, state("working")),
      on("form.cancelled", false, state("working")),
    ]
    return () => offs.forEach((off) => typeof off === "function" && off())
  },
})
