# Category: dot CLI completions

# internal: top-level `dot` subcommands (from the main case in dot.sh)
function _comp_dot_subcommands() {
    sed -n '/^case "\$1" in/,/^esac/p' "$HOME/.dotfiles/dot.sh" |
        grep -oP '^\s+\K[a-z][a-z0-9-]+(?=\))'
}

# internal: installable item names (manifest top-level keys)
function _comp_dot_items() {
    grep -oP '^[a-z0-9][a-z0-9_-]*(?=:)' "$HOME/.dotfiles/manifest.yaml"
}

# internal: profile names (profiles/*.yaml, excluding _templates)
function _comp_dot_profiles() {
    local f
    for f in "$HOME/.dotfiles/profiles/"*.yaml; do
        f="${f##*/}"; f="${f%.yaml}"
        [[ "$f" == _* ]] && continue
        printf '%s\n' "$f"
    done
}

# internal: complete `dot` — subcommands, then install items / profile names
function _comp_dot() {
    if (( COMP_CWORD == 1 )); then
        _comp_reply "$(_comp_dot_subcommands)"
        return
    fi
    case "${COMP_WORDS[1]}" in
        install)
            _comp_reply "$(_comp_dot_items)"
            ;;
        profile)
            if (( COMP_CWORD == 2 )); then
                _comp_reply "list show use"
            elif [[ "${COMP_WORDS[2]}" == "use" ]] && (( COMP_CWORD == 3 )); then
                _comp_reply "$(_comp_dot_profiles)"
            fi
            ;;
    esac
}
complete -F _comp_dot dot
