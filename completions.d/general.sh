# Category: General completions

# internal: complete cdr with directories relative to the git repo root
function _comp_cdr() {
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return
    local IFS=$'\n'
    COMPREPLY=($(cd "$root" 2>/dev/null && compgen -d -- "${COMP_WORDS[COMP_CWORD]}"))
}
complete -F _comp_cdr cdr
