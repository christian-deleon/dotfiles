# ~/.zshrc — Zsh-specific configuration (macOS with Oh My Zsh + Powerlevel10k)

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
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  kube-ps1
)

source "$ZSH/oh-my-zsh.sh"

# ============================
# Homebrew-installed zsh plugins
# ============================
if [[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if [[ -f "$HOMEBREW_PREFIX/share/zsh-you-should-use/you-should-use.plugin.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-you-should-use/you-should-use.plugin.zsh"
fi

if [[ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# ============================
# Cross-platform customizations
# ============================
[[ -f "$HOME/.commonrc" ]] && source "$HOME/.commonrc"

# ============================
# fzf configurations
# ============================
if [[ $commands[fzf] ]]; then
    source <(fzf --zsh)
fi

# ============================
# Powerlevel10k Configuration
# ============================
[[ ! -f "$HOME/dotfiles/.p10k.zsh" ]] || source "$HOME/dotfiles/.p10k.zsh"
