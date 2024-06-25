# ============================
# Source the common configuration file
# ============================
if [ -f $HOME/.commonrc ]; then
    source $HOME/.commonrc
fi


# Initialize zsh completion system
autoload -U compinit
compinit


if [[ -d /opt/homebrew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi


# kubectl configurations
if [[ $commands[kubectl] ]]; then
    source <(kubectl completion zsh)
fi
