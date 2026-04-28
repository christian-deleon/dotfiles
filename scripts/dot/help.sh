# shellcheck shell=bash
# ─── dothelp: interactive fzf browser for aliases and functions ──────────────
# Sourced by dot.sh. Requires DOTFILES_DIR.

dothelp() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf required for interactive search"
        return 1
    fi

    local df="$DOTFILES_DIR"
    local -a entries=()

    # Entry format (tab-separated, 6 fields):
    #   1: display  2: category  3: description  4: type  5: name  6: body
    # fzf shows only field 1 (--with-nth=1) but searches fields 1,2,3,6. Field 6
    # holds the alias command or function source so a query like "kubectl" matches
    # `alias kp='kubectl get pods'` even if the description is just "Get pods".
    local _emit
    _emit() {
        local type="$1" name="$2" category="$3" desc="$4" body="$5"
        local display
        display=$(printf '%-5s %s' "$type" "$name")
        # Normalize body: collapse whitespace (tabs/newlines -> single space) so it
        # stays on one tab-delimited field.
        body="${body//$'\t'/ }"
        body="${body//$'\n'/ }"
        entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$display" "$category" "$desc" "$type" "$name" "$body")")
    }

    # Parse .functions: #####\n# Category\n##### sets category; first comment above a
    # function is its description. Function source is accumulated between the
    # `function NAME()` header and the closing `}` to form the searchable body.
    local fn_category="General"
    local fn_comment=""
    local fn_next_is_cat=false
    local fn_comment_set=false
    local fn_in_body=false
    local fn_name=""
    local fn_desc=""
    local fn_body=""
    while IFS= read -r line; do
        if [[ "$fn_in_body" == true ]]; then
            if [[ "$line" == "}" ]]; then
                _emit "func" "$fn_name" "$fn_category" "$fn_desc" "$fn_body"
                fn_in_body=false
                fn_body=""
            else
                fn_body+=" $line"
            fi
            continue
        fi
        if [[ "$line" =~ ^#{5,}$ ]]; then
            if [[ "$fn_next_is_cat" == true ]]; then
                fn_next_is_cat=false
            else
                fn_next_is_cat=true
            fi
            fn_comment=""
            fn_comment_set=false
        elif [[ "$fn_next_is_cat" == true && "$line" =~ ^#[[:space:]]*(.+) ]]; then
            fn_category="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^#[[:space:]]*(.+) ]]; then
            if [[ "$fn_comment_set" == false ]]; then
                fn_comment="${BASH_REMATCH[1]}"
                fn_comment_set=true
            fi
            fn_next_is_cat=false
        elif [[ "$line" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)\(\) ]]; then
            fn_name="${BASH_REMATCH[1]}"
            fn_desc="${fn_comment:-}"
            fn_body=""
            fn_in_body=true
            fn_comment=""
            fn_comment_set=false
            fn_next_is_cat=false
        elif [[ -z "$line" ]]; then
            fn_comment=""
            fn_comment_set=false
            fn_next_is_cat=false
        fi
    done < "$df/.functions"

    # Parse .aliases: first comment in a consecutive block sets the category; the
    # trailing `  # ...` on an alias line is the per-alias description. The alias
    # command (with outer quotes stripped) becomes the body for search.
    local al_cat="General"
    local al_new_cat_block=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^#[[:space:]]*(.+) ]]; then
            if [[ "$al_new_cat_block" == true ]]; then
                al_cat="${BASH_REMATCH[1]}"
                al_new_cat_block=false
            fi
        elif [[ "$line" =~ ^alias[[:space:]]+([^=]+)=(.+)$ ]]; then
            local al_name="${BASH_REMATCH[1]}"
            local al_rest="${BASH_REMATCH[2]}"
            local al_desc="" al_cmd="$al_rest"
            if [[ "$al_rest" =~ ^(.+)[[:space:]]+#[[:space:]]+(.+)$ ]]; then
                al_cmd="${BASH_REMATCH[1]}"
                al_desc="${BASH_REMATCH[2]}"
            fi
            # Strip outer single or double quotes from the command body.
            if [[ "$al_cmd" =~ ^\'(.*)\'$ ]]; then
                al_cmd="${BASH_REMATCH[1]}"
            elif [[ "$al_cmd" =~ ^\"(.*)\"$ ]]; then
                al_cmd="${BASH_REMATCH[1]}"
            fi
            _emit "alias" "$al_name" "$al_cat" "$al_desc" "$al_cmd"
            al_new_cat_block=false
        elif [[ -z "$line" ]]; then
            al_new_cat_block=true
        fi
    done < "$df/.aliases"

    # Write entries to a temp file so fzf's reload binding can re-filter per keystroke.
    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" RETURN
    printf '%s\n' "${entries[@]}" > "$tmpfile"

    # Preview: description header, "Category · type" subtitle, divider, body.
    # Body = the alias line from .aliases, or the function source from .functions.
    local preview
    preview="
        line={}
        desc=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$3}')
        cat=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$2}')
        type=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$4}')
        name=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$5}')
        [[ -n \"\$desc\" ]] && printf '%s\n' \"\$desc\"
        printf '%s · %s\n' \"\$cat\" \"\$type\"
        printf '%s\n' \"────────────────────────────────────────\"
        if [[ \"\$type\" == \"alias\" ]]; then
            grep -m1 \"^alias \${name}=\" \"$df/.aliases\"
        else
            awk \"/^function[[:space:]]+\${name}[(]/,/^}\$/{print}\" \"$df/.functions\"
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
        local name
        name=$(printf '%s' "$selected" | awk -F'\t' '{print $5}')

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
