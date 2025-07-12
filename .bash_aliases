# Modern command replacements
if command -v eza &>/dev/null; then
    alias ls='eza --icons'
    alias ll='eza -la --icons'
    alias la='eza -a --icons'
    alias lt='eza --tree --icons'
    alias l='eza -alh --color=always --group-directories-first --icons'
fi

if command -v bat &>/dev/null; then
    alias cat='bat -pp'
fi

if command -v fd &>/dev/null; then
    alias find='fd'
fi

if command -v rg &>/dev/null; then
    alias grep='rg'
fi

if command -v bottom &>/dev/null; then
    alias top='bottom'
    alias btm='bottom'
fi

# Git aliases
alias g='git'
alias gs='git status'
alias ga='git add --pass'
alias gc='git commit'
alias gp='git push'
alias gl='git log --all --graph --pretty\
	format: "%c(magenta)%h %C(white) %an %ar%C(auto) %D%n%s%n"'
alias gb='git branch'
alias gd='git diff'
alias gcl='git clone'

# Safety nets
alias r='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# Utils
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%T"'
alias nowdate='date +"%d-%m-%Y"'

# Python
alias py='python3'
alias ipy='ipython3'
alias pip='pip3'
alias venv='python3 -m venv'
alias activate='source ./venv/bin/activate'

# Docker
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias dex='docker exec -it'

# System
alias ports='sudo lsof -i -P -n | grep LISTEN'
alias myip='curl -s https://api.ipify.org && echo'
alias reload='source ~/.bashrc'

alias v='nvim'

# Git Commands
alias gs='git status --short'
alias gd='git diff'
alias ga='git add'
alias gap='git add --pass'
alias gc='git commit'
alias gp='git push'
alias gu='git pull'
alias gl='git log --all --graph --pretty\
        format: "%C(magenta)%h %C(white) %an %ar%C(auto) %D%n%s%n"'
alias gb='git branch'
alias gi='git init'
alias gcl='git clone'

# Safe Symlinking
linkdot() {
  local src="$1"
  local dst="$2"
  local backup_dir="$HOME/.dotfiles-backup"

  if [[ -z "$src" || -z "$dst" ]]; then
    echo "Usage: linkdot <source> <destination>"
    return 1
  fi

  # Ensure full paths
  src=$(realpath -e "$src")
  dst=$(realpath -m "$dst")

  # Make backup if needed
  if [[ -e "$dst" || -L "$dst" ]]; then
    mkdir -p "$backup_dir/$(dirname "${dst#$HOME/}")"
    mv "$dst" "$backup_dir/${dst#$HOME/}"
    echo "🔐 Backed up: $dst → $backup_dir/${dst#$HOME/}"
  fi

  # Create symlink
  ln -s "$src" "$dst"
  echo "🔗 Linked: $dst → $src"
}

