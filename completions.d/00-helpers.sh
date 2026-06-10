# Category: Completion helpers
#
# Shared tab-completion helpers for the custom shell functions/aliases in
# functions.d/ and .aliases. Sourced (in sort order, so this file first) by the
# loader in ~/.commonrc, for BOTH bash and zsh.
#
# Conventions for every completions.d/*.sh fragment:
#   - Write ONCE in bash style: COMP_WORDS / COMP_CWORD / compgen -W /
#     complete -F. zsh runs the same code via bashcompinit (set up in .commonrc).
#   - Do NOT use: compopt, `complete -o default`, BASH_REMATCH, or the
#     bash-completion library helpers (_init_completion, _get_comp_words_by_ref).
#     None survive zsh's bashcompinit.
#   - Name completion functions `_comp_<thing>` and tag each with a single-line
#     `# internal:` comment so scripts/check-descriptions.sh skips it.
#   - Remote sources MUST bound latency (kubectl --request-timeout=2s, etc.) and
#     redirect 2>/dev/null. Empty output -> empty COMPREPLY -> silent no-op; the
#     wrapped function's fzf fallback still covers interactive picking.
#   - Slow enumerations (AWS SSM instance IDs, EKS cluster names) are NOT
#     completed on purpose — fzf already handles those.
#   - Alias names (ta/tk/frk/ws/...) only complete under bash. On zsh the alias
#     expands first and the underlying tool's native completion takes over, so
#     we deliberately do NOT `setopt complete_aliases` (it would also break the
#     `k` -> kubectl completion inheritance).

# internal: set COMPREPLY from a word list ($1) against the current word
function _comp_reply() {
    COMPREPLY=($(compgen -W "$1" -- "${COMP_WORDS[COMP_CWORD]}"))
}

# internal: kubectl context names (local kubeconfig, fast)
function _comp_kctx() {
    kubectl config get-contexts -o name 2>/dev/null
}

# internal: namespaces in the current/context $1 (2s timeout)
function _comp_kns() {
    kubectl ${1:+--context "$1"} get namespaces --request-timeout=2s \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null
}

# internal: pod names in namespace $1 (2s timeout)
function _comp_kpods() {
    kubectl ${1:+-n "$1"} get pods --request-timeout=2s \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null
}

# internal: container names of pod $2 in namespace $1 (2s timeout)
function _comp_kcontainers() {
    kubectl ${1:+-n "$1"} get pod "$2" --request-timeout=2s \
        -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}' 2>/dev/null
}

# internal: AWS profile names from config/credentials + default
function _comp_aws_profiles() {
    {
        grep -hoP '^\[profile \K[^]]+' "$HOME/.aws/config" 2>/dev/null
        grep -hoP '^\[\K[^]]+' "$HOME/.aws/credentials" 2>/dev/null
        echo default
    } | sort -u
}

# internal: common AWS region names (static, fast)
function _comp_aws_regions() {
    printf '%s\n' us-east-1 us-east-2 us-west-1 us-west-2 \
        eu-west-1 eu-west-2 eu-central-1 ca-central-1 sa-east-1 \
        ap-southeast-1 ap-southeast-2 ap-northeast-1 ap-south-1
}

# internal: tmux session names
function _comp_tmux_sessions() {
    tmux list-sessions -F '#S' 2>/dev/null
}

# internal: worktree branch names (worktrunk)
function _comp_wt_branches() {
    wt list --format json 2>/dev/null | jq -r '.[].branch' 2>/dev/null
}
