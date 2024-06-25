# ============================
# Source the common configuration file
# ============================
if [ -f $HOME/.commonrc ]; then
    source $HOME/.commonrc
fi


if [[ -d /opt/homebrew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
