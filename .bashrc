# ~/.bashrc — Bash-specific configuration
# This file is a reference for non-managed systems (Ubuntu, fresh Linux, etc.)
# On Omarchy or other managed systems, add "source ~/.commonrc" to the existing ~/.bashrc
[[ $- != *i* ]] && return

# Shell options
shopt -s histappend
shopt -s checkwinsize

# History
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

# Bash completion
if ! shopt -oq posix; then
    if [[ -f /usr/share/bash-completion/bash_completion ]]; then
        source /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]]; then
        source /etc/bash_completion
    fi
fi

# fzf integration
if command -v fzf &>/dev/null; then
    eval "$(fzf --bash)"
fi

# Starship prompt
if command -v starship &>/dev/null; then
    eval "$(starship init bash)"
fi

# Cross-platform customizations
[[ -f "$HOME/.commonrc" ]] && source "$HOME/.commonrc"
