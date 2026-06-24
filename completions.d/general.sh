# Category: General completions

# internal: complete cdr with directories relative to the git repo root
function _comp_cdr() {
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return
    local IFS=$'\n'
    COMPREPLY=($(cd "$root" 2>/dev/null && compgen -d -- "${COMP_WORDS[COMP_CWORD]}"))
    # Every candidate is a directory: append a trailing slash so you can keep
    # tabbing into subdirs, mirroring native `cd` completion. Paired with the
    # `complete -o nospace` below, which stops bash adding a space after the
    # match. (compopt is blocked under zsh bashcompinit; -o nospace is not, so
    # we set it once globally rather than per-invocation.)
    COMPREPLY=("${COMPREPLY[@]/%//}")
}
complete -o nospace -F _comp_cdr cdr
