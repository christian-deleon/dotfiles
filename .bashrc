# ============================
# If not running interactively, don't do anything
# ============================

[[ $- != *i* ]] && return

# ============================
# Source the common configuration file
# Source the common configuration file
# ============================

if [ -f $HOME/.commonrc ]; then
    source $HOME/.commonrc
fi
if [ -f $HOME/.commonrc ]; then
    source $HOME/.commonrc
fi

# ============================
# Bash-specific configurations
# Bash-specific configurations
# ============================

shopt -s histappend
shopt -s checkwinsize

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# ============================
# Prompt configurations
# ============================

debian_chroot=$(cat /etc/debian_chroot 2> /dev/null)

color_prompt=no
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi

PS1="\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$(parse_git_branch)\n$ "

# ============================
# Aliases and Autocompletion (bash-specific)
# Aliases and Autocompletion (bash-specific)
# ============================

if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# kubectl configurations
if command -v kubectl &>/dev/null; then
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
fi

# fzf configurations
if command -v fzf &>/dev/null; then
    eval "$(fzf --bash)"
fi

export PATH="$PATH:$HOME/.local/bin"
