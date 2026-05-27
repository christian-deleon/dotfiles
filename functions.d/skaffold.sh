# Category: Skaffold

# Skaffold profile picker (dev/debug/run/build/delete)
function sk() {
    if ! command -v skaffold &>/dev/null; then
        echo "Error: skaffold is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi

    if ! command -v yq &>/dev/null; then
        echo "Error: yq is not installed"
        return 1
    fi

    local config="" f
    for f in skaffold.yaml skaffold.yml; do
        [[ -f "$f" ]] && { config="$f"; break; }
    done
    if [[ -z "$config" ]]; then
        echo "No skaffold.yaml in current directory"
        return 1
    fi

    local profiles list
    profiles=$(yq ea '.profiles[]?.name // ""' "$config" 2>/dev/null | grep -v '^$' | sort -u)
    list=$(printf '(no profile)\n%s\n' "$profiles" | grep -v '^$')

    local out key
    out=$(echo "$list" | fzf \
        --prompt="skaffold: " \
        --height=60% \
        --reverse \
        --header=$'ENTER: dev      |  Ctrl-D: debug\nCtrl-R: run     |  Ctrl-B: build\nCtrl-X: delete' \
        --expect=ctrl-d,ctrl-r,ctrl-b,ctrl-x \
        --preview="if [[ {} == '(no profile)' ]]; then yq 'del(.profiles)' '$config'; else yq '.profiles[] | select(.name == \"{}\")' '$config'; fi" \
        --preview-window=right:60%:wrap)
    [[ -z "$out" ]] && return 0

    key=$(head -n1 <<< "$out")
    local profile
    profile=$(tail -n +2 <<< "$out" | head -n1)
    [[ -z "$profile" ]] && return 0

    local -a args=()
    [[ "$profile" != "(no profile)" ]] && args+=(-p "$profile")

    case "$key" in
        ctrl-d) skaffold debug  "${args[@]}" ;;
        ctrl-r) skaffold run    "${args[@]}" ;;
        ctrl-b) skaffold build  "${args[@]}" ;;
        ctrl-x) skaffold delete "${args[@]}" ;;
        "")     skaffold dev    "${args[@]}" ;;
    esac
}
