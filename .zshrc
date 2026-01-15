# ============================
# Homebrew configurations (must be before .commonrc for git, etc.)
# ============================
if [[ -d /opt/homebrew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    fpath=($HOMEBREW_PREFIX/share/zsh/site-functions $fpath)
fi


# ============================
# Source the common configuration file
# ============================
if [ -f $HOME/.commonrc ]; then
    source $HOME/.commonrc
fi


# Initialize zsh completion system
autoload -U compinit
compinit


# kubectl configurations
if [[ $commands[kubectl] ]]; then
    source <(kubectl completion zsh)
fi

export PATH="$PATH:$HOME/.local/bin"
