# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# ============================
# History configurations
# ============================
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend

# ============================
# Terminal configurations
# ============================
shopt -s checkwinsize
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# ============================
# Git branch configurations
# ============================
parse_git_branch() {
     if git rev-parse --git-dir >/dev/null 2>&1; then
         local branch_name="$(git symbolic-ref HEAD 2>/dev/null)" 
         branch_name=${branch_name##refs/heads/} 

         local remote_name="$(git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD))" 
         local ahead_behind="$(git rev-list --left-right --count $branch_name...$remote_name 2>/dev/null)"
         
         local git_status="$(git status 2> /dev/null)"
         local status_indicator=""

         if [[ ! $git_status =~ "nothing to commit" ]]; then
            status_indicator="*"
         fi
         
         if [[ ! -z $branch_name ]]; then
             branch_info=" ($branch_name$status_indicator)"
         fi

         if [[ ! -z $ahead_behind ]]; then
            IFS=$'\t' read -r ahead behind <<< "$ahead_behind"
            if [ "$ahead" -gt 0 ]; then
                ahead_info=" [ahead $ahead]"
            fi
            if [ "$behind" -gt 0 ]; then
                behind_info=" [behind $behind]"
            fi
         fi
         printf "%s%s%s" "$branch_info" "$ahead_info" "$behind_info"
     fi
}

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
# Aliases and Autocompletion
# ============================
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

complete -o default -F __start_kubectl k

# ============================
# Editor configurations
# ============================
export EDITOR="/usr/bin/vim"

# ============================
# Source additional files
# ============================
[ -f ~/.aliases ] && source ~/.aliases
[ -f ~/.functions ] && source ~/.functions
[ -f ~/.exports ] && source ~/.exports

# ============================
# kubectl configurations
# ============================
if command -v kubectl &>/dev/null; then
    source <(kubectl completion bash)
fi
