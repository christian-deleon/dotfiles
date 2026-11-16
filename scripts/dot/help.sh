# shellcheck shell=bash
# ─── dothelp: interactive fzf browser for aliases and functions ──────────────
# Sourced by dot.sh. Requires DOTFILES_DIR.

dothelp() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf required for interactive search"
        return 1
    fi

    local df="$DOTFILES_DIR"

    # Entry format (tab-separated, 6 fields):
    #   1: display  2: category  3: description  4: type  5: name  6: body
    # fzf shows only field 1 (--with-nth=1) but searches fields 1,2,3,6. Field 6
    # holds the alias command or function source so a query like "kubectl" matches
    # `alias kp='kubectl get pods'` even if the description is just "Get pods".
    # Internal helpers (leading underscore) are not user-facing.
    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" RETURN
    awk -f "$df/scripts/descriptions.awk" kind=fn "$df"/functions.d/*.sh kind=alias "$df/.aliases" \
        | awk -F'\t' '
            $1 == "func" && substr($2, 1, 1) != "_" {
                printf "%-5s %s\t%s\t%s\tfunc\t%s\t%s\n", "func", $2, $3, $4, $2, $5
            }
            $1 == "alias" {
                printf "%-5s %s\t%s\t%s\talias\t%s\t%s\n", "alias", $2, $4, $3, $2, $5
            }' > "$tmpfile"

    # Preview: description header, "Category · type" subtitle, divider, body.
    # Body = the alias line from .aliases, or the function source from
    # functions.d/*.sh (search across all fragments).
    local preview
    preview="
        desc={3} cat={2} type={4} name={5}
        [[ -n \"\$desc\" ]] && printf '%s\n' \"\$desc\"
        printf '%s · %s\n' \"\$cat\" \"\$type\"
        printf '%s\n' \"────────────────────────────────────────\"
        if [[ \"\$type\" == \"alias\" ]]; then
            grep -m1 \"^alias \${name}=\" \"$df/.aliases\"
        else
            awk \"/^function[[:space:]]+\${name}[(]/,/^}\$/{print}\" \"$df\"/functions.d/*.sh
        fi
    "

    # Search is externalized: --disabled turns off fzf's own matcher; start/change
    # bindings re-run `fzf --filter` over all fields of the temp file and pipe the
    # results back. This lets us display only field 1 while searching fields 1-3.
    # Use a literal tab in single quotes since the reload shell may be POSIX sh
    # (no $'\t' support).
    local tab=$'\t'
    local reload_cmd
    reload_cmd="q={q}; if [ -z \"\$q\" ]; then cat '$tmpfile'; else fzf --filter=\"\$q\" --delimiter='$tab' --nth=1,2,3,6 < '$tmpfile'; fi"

    local selected
    selected=$(fzf \
            --disabled \
            --query="${1:-}" \
            --prompt=" dotfiles > " \
            --height=80% \
            --reverse \
            --delimiter=$'\t' \
            --with-nth=1 \
            --header=" Shell shortcuts | ENTER: copy to clipboard | Ctrl-H: toggle preview" \
            --preview="$preview" \
            --preview-window=right:70%:wrap \
            --bind="start:reload:$reload_cmd" \
            --bind="change:reload:$reload_cmd" \
            --bind='ctrl-h:toggle-preview' < /dev/null)

    if [[ -n "$selected" ]]; then
        local name="${selected#*$'\t'*$'\t'*$'\t'*$'\t'}"
        name="${name%%$'\t'*}"

        if command -v pbcopy &>/dev/null; then
            printf '%s' "$name" | pbcopy
        elif command -v wl-copy &>/dev/null; then
            printf '%s' "$name" | wl-copy
        elif command -v xclip &>/dev/null; then
            printf '%s' "$name" | xclip -selection clipboard
        else
            echo "$name"
            return 0
        fi

        echo "Copied to clipboard: $name"
    fi
}
