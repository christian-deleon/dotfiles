# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ============================
# Homebrew configurations (must be before Oh My Zsh and .commonrc)
# ============================
if [[ -d /opt/homebrew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    fpath=($HOMEBREW_PREFIX/share/zsh/site-functions $fpath)
fi

# ============================
# Oh My Zsh Configuration
# ============================
# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="powerlevel10k/powerlevel10k"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  kube-ps1
)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# ============================
# Source the common configuration file
# ============================
if [ -f $HOME/.commonrc ]; then
    source $HOME/.commonrc
fi

# ============================
# kubectl configurations
# ============================
if [[ $commands[kubectl] ]]; then
    source <(kubectl completion zsh)
fi

# ============================
# Powerlevel10k Configuration
# ============================
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
