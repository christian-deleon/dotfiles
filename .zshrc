# ============================
# Source the common configuration file
# ============================
if [ -f ~/.commonrc ]; then
    source ~/.commonrc
fi


if [[ -d /opt/homebrew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
