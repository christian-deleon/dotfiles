# Category: Tmux

# internal: expand AI_TOOL aliases + optional prompt to a command line
function _tav_expand_launch() {
    # AI_TOOL values are often aliases (gra → grok --always-approve). Expand
    # them here (interactive shell has BASH_ALIASES) so we can later launch via
    # a non-interactive bash that will not expand aliases.
    local ai_cmd=$1 prompt=$2
    local first=${ai_cmd%% *}
    local rest= expanded=

    [[ $ai_cmd == *' '* ]] && rest=${ai_cmd#* }

    if [[ -n ${BASH_ALIASES[$first]+x} ]]; then
        expanded=${BASH_ALIASES[$first]}
        [[ -n $rest ]] && expanded+=" $rest"
    else
        expanded=$ai_cmd
    fi

    if [[ -n $prompt ]]; then
        printf '%s %q' "$expanded" "$prompt"
    else
        printf '%s' "$expanded"
    fi
}

# internal: schedule post-start scrub of leaked DA text in AI prompt
function _tav_schedule_da_scrub() {
    # Grok treats Device Attributes replies as key input: its CSI parser eats
    # ESC/[/> and leaves the body in the prompt (Alacritty `\e[>0;2600;1c` →
    # `0;2600;1c`; tmux → `84;0;0c`). Scrub with C-u only when that fingerprint
    # is visible, so we never wipe real typing. run-shell -b is owned by the
    # tmux server and survives the pane being respawned (which kills tav's shell).
    local pane=$1 delay=$2
    # Compact one-liner for run-shell; pane id is %N (safe, no spaces).
    # Match DA-body leftovers via grep (case patterns treat `;` as a clause
    # terminator, so we can't use `case … *[0-9];[0-9]*c*`).
    # Always end with `true`: grep -q exits 1 when there's no junk, and tmux
    # run-shell prints "'…' returned 1" into a pane until the user hits C-c.
    tmux run-shell -b "sleep $delay; { tmux capture-pane -t $pane -p 2>/dev/null | grep -F '❯' | head -1 | grep -qE '[0-9]+;[0-9]+([;0-9]*)c' && tmux send-keys -t $pane C-u; true; }"
}

# internal: respawn pane running AI without interactive-shell DA race
function _tav_respawn_ai() {
    # Two layers of defense against DA-reply garbage in the AI prompt:
    # 1) Launch via noprofile/norc bash (no ble.sh) after a quiet-period drain.
    # 2) After the TUI is up, scrub the prompt if a leaked DA body is present.
    local pane=$1 dir=$2 launch=$3
    local inner outer shell quiet_drain

    # Wait until stdin is quiet for ~150ms (max ~1s) so late CSI/OSC replies
    # from pane splits / sibling apps are drained before the AI starts.
    quiet_drain='
deadline=$((SECONDS + 1))
quiet=0
while (( SECONDS < deadline )); do
  if IFS= read -r -t 0.05 -n 1 _; then
    quiet=0
  else
    quiet=$((quiet + 1))
    # 3 consecutive timeouts ≈ 150ms of silence
    (( quiet >= 3 )) && break
  fi
done
clear 2>/dev/null || true
'
    inner="${quiet_drain}${launch}"
    shell=${SHELL:-bash}
    outer="bash --noprofile --norc -c $(printf '%q' "$inner"); exec $(printf '%q' "$shell") -i"

    # Two passes: early (TUI init probes) and late (nvim sibling term queries).
    _tav_schedule_da_scrub "$pane" 0.5
    _tav_schedule_da_scrub "$pane" 1.3

    # Must be last: -k kills the current process (often the shell running tav).
    tmux respawn-pane -k -t "$pane" -c "$dir" "$outer"
}

# Open tmux 3-pane layout with an AI tool and LazyVim
function tav() {
    [[ -z "$TMUX" ]] && { echo "You must start tmux to use tav."; return 1; }

    # Usage: tav [-t|--tool <ai_cmd>] [prompt...]
    #   bare positional args are the initial prompt (e.g. tav "add a contact page");
    #   -t/--tool overrides $AI_TOOL for this call (e.g. tav -t oc "...").
    #   Use `--` to force a prompt that begins with a dash.
    local ai_cmd=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--tool) ai_cmd="$2"; shift 2 ;;
            --)        shift; break ;;
            -*)        echo "tav: unknown option '$1'" >&2; return 1 ;;
            *)         break ;;
        esac
    done
    local prompt="$*"

    ai_cmd="${ai_cmd:-${AI_TOOL:-}}"
    if [[ -z "$ai_cmd" ]]; then
        echo "Error: no AI tool set. Run 'dot ai-tool' or pass one explicitly: tav -t cld" >&2
        return 1
    fi

    local launch current_dir top_left top_right
    launch=$(_tav_expand_launch "$ai_cmd" "$prompt")
    current_dir=${PWD}
    top_left=$TMUX_PANE

    tmux rename-window -t "$top_left" "$(basename "$current_dir")"

    # Vertical divider at ~35%: new right pane takes 65%, full height
    top_right=$(tmux split-window -h -p 65 -t "$top_left" -c "$current_dir" -P -F '#{pane_id}')

    # Horizontal divider at ~32% from bottom in the left column only
    tmux split-window -v -p 32 -t "$top_left" -c "$current_dir"

    # Open Neovim on the project dir and drop straight into the LazyGit view
    # (same as <leader>gg / the `nvg` alias). vim.schedule defers until Snacks
    # is set up; quitting LazyGit leaves you in the project explorer.
    tmux send-keys -t "$top_right" 'nvim . -c "lua vim.schedule(function() Snacks.lazygit() end)"' C-m

    # Focus AI pane, then respawn it (kills this shell — must be last).
    tmux select-pane -t "$top_left"
    _tav_respawn_ai "$top_left" "$current_dir" "$launch"
}

# Open tmux 4-pane layout with an AI tool, LazyVim, and k9s
function tavk() {
    [[ -z "$TMUX" ]] && { echo "You must start tmux to use tavk."; return 1; }

    # Usage: tavk [-t|--tool <ai_cmd>] [prompt...] — see tav for flag details.
    local ai_cmd=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--tool) ai_cmd="$2"; shift 2 ;;
            --)        shift; break ;;
            -*)        echo "tavk: unknown option '$1'" >&2; return 1 ;;
            *)         break ;;
        esac
    done
    local prompt="$*"

    ai_cmd="${ai_cmd:-${AI_TOOL:-}}"
    if [[ -z "$ai_cmd" ]]; then
        echo "Error: no AI tool set. Run 'dot ai-tool' or pass one explicitly: tavk -t cld" >&2
        return 1
    fi

    local launch current_dir top_left top_right bottom_right
    launch=$(_tav_expand_launch "$ai_cmd" "$prompt")
    current_dir=${PWD}
    top_left=$TMUX_PANE

    tmux rename-window -t "$top_left" "$(basename "$current_dir")"

    # Vertical divider at ~35%: new right pane takes 65%
    top_right=$(tmux split-window -h -p 65 -t "$top_left" -c "$current_dir" -P -F '#{pane_id}')

    # Horizontal divider at ~32% from bottom in both columns
    tmux split-window -v -p 32 -t "$top_left" -c "$current_dir"
    bottom_right=$(tmux split-window -v -p 32 -t "$top_right" -c "$current_dir" -P -F '#{pane_id}')

    # Open Neovim on the project dir and drop straight into the LazyGit view
    # (same as <leader>gg / the `nvg` alias). See tav for the rationale.
    tmux send-keys -t "$top_right" 'nvim . -c "lua vim.schedule(function() Snacks.lazygit() end)"' C-m
    tmux send-keys -t "$bottom_right" "k9s" C-m

    # Focus AI pane, then respawn it (kills this shell — must be last).
    tmux select-pane -t "$top_left"
    _tav_respawn_ai "$top_left" "$current_dir" "$launch"
}

# Tmux session picker (switch/kill/rename via keybinds)
function ts() {
    if ! command -v tmux &>/dev/null; then
        echo "Error: tmux is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi

    if ! tmux list-sessions &>/dev/null; then
        echo "No tmux sessions found"
        return 1
    fi

    local out key
    out=$(tmux list-sessions -F "#{session_name}: #{session_windows} windows (created #{t:session_created})" \
        | fzf --multi \
            --prompt="tmux session: " \
            --height=60% \
            --reverse \
            --header=$'ENTER: switch  |  Ctrl-X: kill (TAB to multi)\nCtrl-R: rename' \
            --expect=ctrl-x,ctrl-r \
            --preview='tmux capture-pane -ep -t {1}' \
            --preview-window=right:60%:wrap)
    [[ -z "$out" ]] && return 0

    # `--expect` puts the pressed key on line 1 (empty for ENTER); selections follow.
    key=$(head -n1 <<< "$out")
    local -a picks=()
    local line name
    while IFS= read -r line; do
        name="${line%%:*}"
        [[ -n "$name" ]] && picks+=("$name")
    done < <(tail -n +2 <<< "$out")

    (( ${#picks[@]} )) || return 0

    case "$key" in
        ctrl-x)
            local current=""
            [[ -n "$TMUX" ]] && current=$(tmux display-message -p '#S')

            local kill_current=0 t
            for t in "${picks[@]}"; do
                if [[ "$t" == "$current" ]]; then
                    kill_current=1
                    continue
                fi
                tmux kill-session -t "$t" && echo "killed: $t"
            done

            (( kill_current )) || return 0

            # Switch the attached client to any surviving session before killing
            # current, so the user isn't detached.
            local survivor
            survivor=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
                | grep -vxF "$current" | head -n1)
            if [[ -z "$survivor" ]]; then
                echo "warning: '$current' is the only remaining session; skipping to avoid detach" >&2
                return 1
            fi
            tmux switch-client -t "$survivor"
            tmux kill-session -t "$current" && echo "killed: $current (switched to $survivor)"
            ;;
        ctrl-r)
            local target="${picks[0]}" new
            read -r -p "rename '$target' → " new
            [[ -z "$new" ]] && { echo "cancelled"; return 0; }
            tmux rename-session -t "$target" "$new" && echo "renamed: $target → $new"
            ;;
        "")
            local target="${picks[0]}"
            if [[ -n "$TMUX" ]]; then
                tmux switch-client -t "$target"
            else
                tmux attach -t "$target"
            fi
            ;;
    esac
}

# Switch tmux window across all sessions with fzf
function tw() {
    if ! command -v tmux &>/dev/null; then
        echo "Error: tmux is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi

    if ! tmux list-sessions &>/dev/null; then
        echo "No tmux sessions found"
        return 1
    fi

    local target
    target=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}#{?window_active, *,}' \
        | fzf \
            --prompt="tmux window: " \
            --height=60% \
            --reverse \
            --preview='tmux capture-pane -ep -t {1}' \
            --preview-window=right:60%:wrap \
        | awk '{print $1}')
    [[ -z "$target" ]] && return 0

    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$target"
    else
        tmux attach -t "$target"
    fi
}
