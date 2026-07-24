# Category: Git

# Git Clone and cd into it
function gc() {
    git clone "$1" && cd "$(basename "$1" .git)"
}

# Git Clone and cd into it and open in Cursor
function gcc() {
    gc "$1" && cursor .
}

# Git Clone and cd into it and open in VS Code
function gcv() {
    gc "$1" && code .
}

# Git Status with short output
function gs() {
    git status -s
}

# Generate .gitignore via gitignore.io (vim, macOS, vscode)
function gi() {
    local gitignore_file
    local content
    local response
    local default_templates=("vim" "macos" "visualstudiocode")
    local user_templates=()
    local all_templates=()

    gitignore_file=".gitignore"

    # Check if .gitignore already exists
    if [ -f "$gitignore_file" ]; then
        echo "A .gitignore file already exists in the current directory"
        echo -n "Do you want to overwrite it? (y/n): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
    fi

    # Parse user input - handle comma-separated arguments
    if [ -n "$*" ]; then
        # Split by comma and process each template
        local IFS=','
        for template in $*; do
            # Trim whitespace (pure shell method)
            template="${template#"${template%%[![:space:]]*}"}"
            template="${template%"${template##*[![:space:]]}"}"

            if [ -n "$template" ]; then
                template_lower=$(echo "$template" | tr '[:upper:]' '[:lower:]')

                # Check if this matches a default (case-insensitive)
                local is_default=false
                for default in "${default_templates[@]}"; do
                    default_lower=$(echo "$default" | tr '[:upper:]' '[:lower:]')
                    if [ "$template_lower" = "$default_lower" ]; then
                        is_default=true
                        break
                    fi
                done

                # Only add non-defaults to user_templates
                if [ "$is_default" = false ]; then
                    user_templates+=("$template")
                fi
            fi
        done
    fi

    # Build final template list: user templates + defaults
    all_templates=("${user_templates[@]}" "${default_templates[@]}")

    # Join with comma for API call
    local template_string
    IFS=','
    template_string="${all_templates[*]}"
    unset IFS

    # Fetch gitignore.io content
    content="$(curl -sL "https://www.toptal.com/developers/gitignore/api/$template_string")"

    # Check if the API call was successful
    if echo "$content" | grep -q "ERROR:"; then
        echo "Error: Invalid gitignore templates" >&2
        echo "$content" >&2
        return 1
    fi

    # Append common patterns from GitHub raw URL
    local common_patterns
    common_patterns="$(curl -sL https://raw.githubusercontent.com/christian-deleon/dotfiles/refs/heads/main/.gitignore.dotfiles 2>/dev/null)"
    if [ -n "$common_patterns" ]; then
        content="$content"$'\n\n'"$common_patterns"
    fi

    # Write to .gitignore file
    echo "$content" > "$gitignore_file"
    echo "Created/updated .gitignore in current directory"
}


# OMZ git plugin aliases gcb='git checkout -b'; drop it so our function wins.
unalias gcb 2>/dev/null
# Clone a repo as a bare repo for worktree workflows
function gcb() {
    if [[ -z "$1" ]]; then
        echo "Usage: gcb <repo-url>"
        echo "   ex: gcb git@github.com:user/repo.git"
        return 1
    fi

    local repo_url="$1"
    local repo_name="$(basename "$repo_url" .git)"

    # Clone bare into <repo>/.git (worktrunk convention)
    git clone --bare "$repo_url" "${repo_name}/.git" || return 1

    # Configure remote to fetch all branches (bare repos need this)
    git -C "${repo_name}/.git" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    # Fetch all branches to have latest refs
    git -C "${repo_name}/.git" fetch origin

    echo "Bare repo cloned to: ${repo_name}/"
    cd "$repo_name" || return 1
}
