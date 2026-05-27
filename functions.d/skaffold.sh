# Category: Skaffold

# Skaffold picker over all configs+profiles in tree
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

    # Discover every Skaffold Config reachable from cwd by content match
    # (`apiVersion: skaffold/`) so we catch configs that aren't literally
    # named skaffold.yaml (e.g. modules under infra/skaffold/*.yaml).
    # `git ls-files` inside a repo is fast + gitignore-aware; otherwise find.
    local -a configs=()
    if git rev-parse --git-dir &>/dev/null; then
        mapfile -t configs < <(
            git ls-files '*.yaml' '*.yml' 2>/dev/null \
                | xargs grep -l 'apiVersion: skaffold/' 2>/dev/null
        )
    else
        mapfile -t configs < <(
            find . -type f \( -name '*.yaml' -o -name '*.yml' \) \
                -not -path '*/node_modules/*' \
                -not -path '*/.git/*' 2>/dev/null \
                | xargs grep -l 'apiVersion: skaffold/' 2>/dev/null
        )
    fi

    if (( ${#configs[@]} == 0 )); then
        echo "No Skaffold configs found under $(pwd)"
        return 1
    fi

    # One row per (config, profile) pair, with "(no profile)" as the
    # default per-config row.
    local list cfg
    list=$(
        for cfg in "${configs[@]}"; do
            printf '%s :: (no profile)\n' "$cfg"
            yq ea '.profiles[]?.name // ""' "$cfg" 2>/dev/null \
                | grep -v '^$' \
                | sort -u \
                | while IFS= read -r prof; do
                      printf '%s :: %s\n' "$cfg" "$prof"
                  done
        done
    )

    local out key
    out=$(echo "$list" | fzf \
        --prompt="skaffold: " \
        --height=70% \
        --reverse \
        --header=$'ENTER: dev      |  Ctrl-D: debug\nCtrl-R: run     |  Ctrl-B: build\nCtrl-X: delete' \
        --expect=ctrl-d,ctrl-r,ctrl-b,ctrl-x \
        --preview='line={}; path=${line% :: *}; prof=${line##* :: }; if [[ "$prof" == "(no profile)" ]]; then yq "del(.profiles)" "$path"; else yq ".profiles[] | select(.name == \"$prof\")" "$path"; fi' \
        --preview-window=right:60%:wrap)
    [[ -z "$out" ]] && return 0

    key=$(head -n1 <<< "$out")
    local line
    line=$(tail -n +2 <<< "$out" | head -n1)
    [[ -z "$line" ]] && return 0

    local path profile
    path="${line% :: *}"
    profile="${line##* :: }"

    local -a args=(-f "$path")
    [[ "$profile" != "(no profile)" ]] && args+=(-p "$profile")

    case "$key" in
        ctrl-d) skaffold debug  "${args[@]}" ;;
        ctrl-r) skaffold run    "${args[@]}" ;;
        ctrl-b) skaffold build  "${args[@]}" ;;
        ctrl-x) skaffold delete "${args[@]}" ;;
        "")     skaffold dev    "${args[@]}" ;;
    esac
}
