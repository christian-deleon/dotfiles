#!/usr/bin/env bash
# Record the agent session's state on its tmux pane for `wto ls` / `wto send`.
# Usage: session_state.sh <starting|working|idle|blocked|exited>
# Registered for Grok by dotfiles.json and for Claude by ensure_claude_settings.
# Must stay silent: Claude adds a hook's stdout to the model's context on some
# events. Always exits 0 so a tmux hiccup never blocks the agent.

state=${1:-}
payload=$(cat 2>/dev/null || true)

[[ -n ${TMUX_PANE-} && -n $state ]] || exit 0

# Grok fires Stop again at session end (reason channel_closed / shutdown);
# SessionEnd records that as exited, so a late idle must not overwrite it.
# A Grok subagent's turn end is not the session's.
if [[ $state == idle && ( $payload == *'"reason"'* || $payload == *'"subagentType"'* ) ]]; then
    skip=$(jq -r '(.subagentType // "") != "" or ((.reason // "end_turn") != "end_turn")' \
        <<<"$payload" 2>/dev/null || true)
    [[ $skip == true ]] && exit 0
fi

tmux set-option -p -t "$TMUX_PANE" @ai_state "$state" \; \
    set-option -p -t "$TMUX_PANE" @ai_state_at "$(date +%s)" >/dev/null 2>&1 || true
exit 0
