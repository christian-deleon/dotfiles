#!/usr/bin/env bash
# Stop gate for issue sessions. A branch whose last segment starts with an
# issue number (fix/142-retry-backoff) and whose own commits are now in the
# default branch may not end a turn while that issue is still open on the
# tracker; the closeout skill's "Close the issue" step is what clears it.
# Registered for Claude by ensure_claude_settings and for Grok by dotfiles.json.
#
# Blocks at most once per stop: a stop the gate already bounced
# (stop_hook_active / stopHookActive) goes through. Fails open: whatever it
# cannot determine allows the stop, with a note to the user when the tracker
# could not be asked.

payload=$(cat 2>/dev/null || true)

allow_with_note() {
    jq -n --arg m "$1" '{systemMessage: $m}' 2>/dev/null || true
    exit 0
}

out=$(jq -r 'if (.stop_hook_active // .stopHookActive // false)
        or ((.subagentType // "") != "")
        or ((.reason // "end_turn") != "end_turn")
    then "skip" else "go", (.cwd // "") end' <<<"$payload" 2>/dev/null)
[[ $out == go* ]] || exit 0
cwd=${out#go}
cwd=${cwd#$'\n'}
cd -- "${cwd:-$PWD}" 2>/dev/null || exit 0

branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0
[[ ${branch##*/} =~ ^([0-9]+)(-|$) ]] || exit 0
issue=${BASH_REMATCH[1]}

# Same directory `wto dir` prints. A saved draft means the owner is reviewing
# the closing comment, so the session may wait. The closed stamp keeps a
# merged branch from asking the tracker again on every later turn.
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
close_dir="$common/orchestrate/issue-close"
draft="$close_dir/${branch//\//-}.md"
stamp="$close_dir/${branch//\//-}.closed"
[[ -e $stamp ]] && exit 0

# A merged branch and a fresh one both sit at or behind the default branch;
# only a "commit" entry in the branch reflog shows it did work.
reflog="$common/logs/refs/heads/$branch"
if [[ -f $reflog ]]; then
    grep -q $'\tcommit' -- "$reflog" || exit 0
else
    git reflog show --format=%gs "refs/heads/$branch" 2>/dev/null | grep -q '^commit' || exit 0
fi

default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    && default=${default#origin/}
if [[ -z $default ]]; then
    # A bare project's HEAD names the branch it was cloned on.
    default=$(git --git-dir="$common" symbolic-ref --quiet --short HEAD 2>/dev/null)
fi
[[ -n $default && $default != "$branch" ]] || exit 0
git merge-base --is-ancestor HEAD "refs/heads/$default" 2>/dev/null || exit 0

[[ -f $draft ]] && exit 0

url=$(git remote get-url origin 2>/dev/null) \
    || allow_with_note "Could not check whether issue #$issue is closed: this repo has no origin remote. If it is still open, close it from this session."
case $url in
    *://*)
        rest=${url#*://}
        rest=${rest#*@}
        host=${rest%%/*}
        repo=${rest#*/}
        ;;
    *@*:*)
        rest=${url#*@}
        host=${rest%%:*}
        repo=${rest#*:}
        ;;
    *) allow_with_note "Could not check whether issue #$issue is closed: origin ($url) does not name a forge. If it is still open, close it from this session." ;;
esac
host=${host%%:*}
repo=${repo%.git}
repo=${repo%/}

# Which CLI reads this host's tracker, remembered per host after a good read
# so later turns skip the probing; a failed read forgets it.
tracker_cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/issue-tracker/$host"
gh_hosts="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml"
state=''
tool=''
login=''
read -r tool login 2>/dev/null <"$tracker_cache"
if [[ -z $tool ]]; then
    # gh's hosts.yml names every host it has a login for; `gh auth status`
    # would validate the token over the network instead.
    if [[ $host == github.com ]] || { command -v gh >/dev/null && grep -qxF -- "$host:" "$gh_hosts" 2>/dev/null; }; then
        tool=gh
    elif command -v tea >/dev/null \
        && login=$(tea logins list --output json 2>/dev/null | jq -r --arg h "$host" '
            [.[] | select((.url | sub("^[a-z]+://"; "") | sub("[:/].*$"; "")) == $h or .ssh_host == $h)][0].name // empty') \
        && [[ -n $login ]]; then
        tool=tea
    elif [[ $host == gitlab.com ]] || { command -v glab >/dev/null && glab auth status --hostname "$host" >/dev/null 2>&1; }; then
        tool=glab
    fi
fi
case $tool in
    gh) state=$(timeout 10 gh issue view "$issue" -R "$host/$repo" --json state -q .state 2>/dev/null) ;;
    tea)
        state=$(timeout 10 tea issues "$issue" --login "$login" --repo "$repo" --comments=false --output json 2>/dev/null \
            | jq -r '.state // empty' 2>/dev/null)
        ;;
    glab) state=$(timeout 10 glab issue view "$issue" -R "$url" --output json 2>/dev/null | jq -r '.state // empty' 2>/dev/null) ;;
esac
state=${state,,}
if [[ -n $state ]]; then
    mkdir -p -- "${tracker_cache%/*}" 2>/dev/null \
        && printf '%s %s\n' "$tool" "$login" >"$tracker_cache" 2>/dev/null
else
    rm -f -- "$tracker_cache" 2>/dev/null
fi

case $state in
    closed)
        mkdir -p -- "$close_dir" 2>/dev/null && : >"$stamp" 2>/dev/null
        exit 0
        ;;
    open | opened) ;;
    *)
        if [[ -z $tool ]]; then
            allow_with_note "Could not check whether issue #$issue is closed: no logged-in gh, tea, or glab knows $host. If it is still open, close it from this session."
        fi
        allow_with_note "Could not check whether issue #$issue on $host/$repo is closed: $tool could not read it (offline, VPN down, or not logged in). If it is still open, close it from this session."
        ;;
esac

reason="$branch is merged into $default, but issue #$issue on $host/$repo is still open. \
Close it now, as the closeout skill's \"Close the issue\" step says: a short closing comment \
(what landed, the merge commit, how it was verified), then close the issue. If the owner must \
approve that comment first, save the draft to $draft and ask for their OK. If this branch's \
work did not actually land, tell the owner instead of closing anything."
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
