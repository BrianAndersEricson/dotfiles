export DOTFILES_DIR="$HOME/.src/dotfiles"

# Only run if interactive
case $- in
    *i*) ;;
      *) return;;
esac

# History settings
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

# Enable recursive globbing
shopt -s globstar

# Bash homescreen
[ -f "$DOTFILES_DIR/.config/shell_start" ] && . "$DOTFILES_DIR/.config/shell_start"

# Enhanced 'less'
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Load user-defined aliases
[ -f ~/.bash_aliases ] && . ~/.bash_aliases

# FuzzyFind
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# Zoxide
eval "$(zoxide init bash)"

# Bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Starship prompt
eval "$(starship init bash)"
