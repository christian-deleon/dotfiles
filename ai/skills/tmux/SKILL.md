---
name: tmux
description: Find, read, and send input to tmux panes — run a command in another pane or window, read what a pane shows, message an agent session in a pane (`wto send` or native messaging), and test against an isolated tmux server. Use for 'run this in that pane', 'send this to the session in window X', 'what does that window show', send-keys, capture-pane, or before typing into any pane that is not your own.
---

# tmux — reading and driving panes

The user works in tmux: one window per git worktree, laid out by `tav` with an
agent on the left, a shell below it, and nvim on the right. You run in one of
those panes. This skill covers acting on the others: reading what they show,
typing into a shell, and getting a message to the agent in another window.

The most common failure is typing into the wrong place: a pane that is running
something other than you assumed (an agent waiting on a question takes your text
as its answer; an agent that exited left a shell that runs your text as
commands). The second is targeting by name: window names repeat and can contain
dots, and session names match by prefix. The third is touching your own pane.

Type into another pane only when the user asks for that pane, or a skill you are
following says to. It acts in someone's live session.

## How tmux is put together

| Level | Id | Notes |
|---|---|---|
| Server | its socket | One per socket. `$TMUX` holds the socket path of the server you run in; `-L name` or `-S path` picks another. |
| Session | `$3` | Named; `-t name` matches by prefix, so use `-t =name` for an exact match. |
| Window | `@12` | Named after the branch with `/` → `-`. A name with a dot (`fix-1.2`) is misread as `window.pane`. |
| Pane | `%110` | Unique on its server, never reused while it runs. |

Target panes and windows by id, never by `session:window` name. Ids come from
`-P -F '#{pane_id}'` when you create something, or from a listing. Your own pane
is `$TMUX_PANE`.

## Find the pane

```bash
tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_name} #{pane_current_command} #{pane_current_path} #{@ai_tool} #{@ai_state}'
```

- `pane_current_command`: what runs in it now. An agent pane often shows `bash`
  too, since the launcher wraps the agent, so a shell name alone does not mean
  a prompt; check `@ai_tool` and `alternate_on` as well.
- `@ai_tool`, `@ai_wt`, `@ai_state`: tags `tav` and `wto` set on agent panes.
  `@ai_state` is `starting`, `working`, `idle`, `blocked` (waiting on a
  question), or `exited`.
- In a worktrunk project, `wto ls --json` joins this to the worktrees: each
  entry's `session.pane` is that worktree's agent pane.
- `#{alternate_on}` is 1 while a full-screen program (nvim, an agent TUI, less)
  owns the pane; typed text goes to that program, not a shell.

## Read a pane

```bash
tmux capture-pane -p -J -t %110 -S -200 | grep -v '^\s*$' | tail -40
```

`-J` joins wrapped lines, `-S -200` starts 200 lines back. To wait for output,
poll with a timeout (`until tmux capture-pane -p -t %110 | grep -q 'done'; do
sleep 2; done` under `timeout`), never one long sleep.

## Send to a shell pane

Check first: `@ai_tool` is empty, `alternate_on` is 0, and the last lines of
`capture-pane` end at a prompt. Then:

```bash
tmux send-keys -t %111 -l 'just test'
tmux send-keys -t %111 Enter
```

- `-l` sends the text literally; without it, words like `Enter` or `C-c` become
  keys. Send `Enter` as its own call.
- One line only. A line editor (the user's bash runs ble.sh) can open a
  multi-line edit and wait; for anything longer, write a script file and send
  `bash /path/to/script`.
- Read the result with `capture-pane` before you report it.
- `C-c` interrupts whatever runs there; send it only when the user asks.

For a long block into a program that accepts pasted text, paste it whole:
`tmux load-buffer -b mybuf file`, then `tmux paste-buffer -d -p -b mybuf -t %111`
(`-p` uses bracketed paste so the program sees one paste, `-d` drops the buffer).

## Send to an agent session

Never type into an agent's pane with `send-keys`. Its state decides what your
text becomes, and only the tools below check it:

| Way | When |
|---|---|
| The harness's own messaging (Claude Code: load the deferred `ListAgents` and `SendMessage`) | The target is a session of the same harness. Pick the `ListAgents` row whose tmux pane matches; names are often generated. First line: `wto header` (or `wto header --relay` for the user's words). |
| `wto send <branch> [-f file]`, `--main`, `--all` | Any harness, in a worktrunk project. Adds the header, pastes as one message, and refuses rather than risk it: exit 6 blocked on a question, 5 exited, 7 just launched (retry in about 15s), 4 no session. Never `--force` unless the user says so. OpenCode sessions get it through the OpenCode server, queued behind a running turn. |

The receiving agent treats a headed message as another session's words, not the
user's (the session-messages rule). To have an agent run something, send it the
request as a message; do not type the command into its pane.

## Run a command in a session for the user

"Run X in the feat/login window":

1. Find that window's panes. Use the shell pane (below the agent in a `tav`
   layout), not the agent pane.
2. Check it is at a prompt in the right directory. If it is busy, say what it is
   running and ask.
3. Send the command, wait for it to finish, read the output, and report it.

If the user means the agent there should do it, send the agent a message
instead.

## Create, replace, and close

- `tmux new-window -d -c <dir> -P -F '#{pane_id}'` and `split-window -d` create
  without moving the user's focus; without `-d` they switch the client.
- `respawn-pane -k` kills what runs in the pane first. Never respawn your own
  pane or one with a live agent; `wto layout` refuses an agent pane for this
  reason.
- Closing a window or session ends its programs. Confirm with the user unless you
  created it in this task.
- `pkill -f <pattern>` also matches your own shell, whose command line contains
  the pattern. Kill by pid.

## Test against an isolated server

Every plain `tmux` command goes to the user's real server unless told otherwise.
For a test, point everything, child shells included, at a server of its own:

```bash
export TMUX_TMPDIR=/tmp/claude-$(id -u)/t   # keep the path short: socket paths max out near 100 characters
unset TMUX TMUX_PANE
tmux new-session -d -s test -c "$dir"
tmux display-message -p '#{socket_path}'     # check it before going on
```

- A `tmux` stand-in first in `PATH` is not enough: interactive shells rebuild
  `PATH` from their startup files and reach the real server again.
- Claude Code's native messaging spans every session on the machine and matches
  by pane id. Pane ids restart at `%0` on a new server, so create and close
  windows until its ids pass the real server's highest before starting agents.
- After the test, check the real server (`tmux -S /tmp/tmux-$(id -u)/default
  ls`) holds only what it held before, and kill the test server.

## Do not

- Type into any pane the user did not point you at, or into your own.
- `send-keys` into an agent session; use native messaging or `wto send`.
- Target by `session:window` name, or by a bare session name that can match a
  prefix.
- Send a multi-line command into an interactive shell.
- Kill a session, window, or pane you did not create without asking.
