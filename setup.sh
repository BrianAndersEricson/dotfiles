#!/bin/bash
set -e

# === CONFIGURATION ===
DOTFILES_DIR="$HOME/.src/dotfiles"
CONFIG_TARGET="$HOME/.config"
SCRIPTS_DIR="$DOTFILES_DIR/scripts"

# === FUNCTION: Detect OS ===
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/arch-release ]; then
        OS="arch"
    elif [ -f /etc/debian_version ]; then
        OS="ubuntu"
    else
        echo "❌ Unsupported OS. This script supports Ubuntu and Arch Linux."
        exit 1
    fi
    echo "🐧 Detected OS: $OS"
}

# === FUNCTION: Install packages ===
install_packages() {
    echo "📦 Installing essential tools..."
    
    case "$OS" in
        "ubuntu"|"debian")
            sudo apt update && sudo apt install -y \
                curl \
                git \
                tmux \
                fzf \
                ripgrep \
                bat \
                zoxide \
                build-essential \
                unzip \
                pkg-config \
                libtool \
                libtool-bin \
                autoconf \
                automake \
                cmake \
                g++ \
                python3 \
                python3-pip \
                ninja-build \
                gpg
            ;;
        "arch"|"manjaro")
            sudo pacman -Syu --noconfirm \
                curl \
                git \
                tmux \
                fzf \
                ripgrep \
                bat \
                zoxide \
                base-devel \
                unzip \
                pkg-config \
                libtool \
                autoconf \
                automake \
                cmake \
                gcc \
                python \
                python-pip \
                ninja \
                gnupg
            ;;
        *)
            echo "❌ Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    echo "✅ Packages installed."
    
    # Neovim: latest from GitHub (AppImage)
    echo "📝 Checking Neovim version..."
    INSTALLED_NVIM_VER=$(command -v nvim >/dev/null 2>&1 && nvim --version | head -n1 | awk '{print $2}' || echo "not_installed")
    LATEST_NVIM_VER=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep 'tag_name' | cut -d '"' -f4 | sed 's/^v//')
    
    if [ "$INSTALLED_NVIM_VER" != "$LATEST_NVIM_VER" ]; then
        echo "⬇️ Installing latest Neovim $LATEST_NVIM_VER..."
        mkdir -p "$HOME/.local/bin"
        curl -Lo "$HOME/.local/bin/nvim" https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
        chmod u+x "$HOME/.local/bin/nvim"
    else
        echo "✅ Latest Neovim already installed ($INSTALLED_NVIM_VER)"
    fi
    
    # Ensure ~/.local/bin is in PATH
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
}

# === FUNCTION: Setup Git ===
setup_git() {
    echo "🔧 Setting up Git configuration..."
    
    # Check if git is already configured
    if git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; then
        echo "✅ Git already configured:"
        echo "   Name: $(git config --global user.name)"
        echo "   Email: $(git config --global user.email)"
        read -p "Do you want to reconfigure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # Prompt for git configuration
    read -p "Enter your Git name: " GIT_NAME
    read -p "Enter your Git email: " GIT_EMAIL
    
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    
    echo "✅ Git configured with:"
    echo "   Name: $GIT_NAME"
    echo "   Email: $GIT_EMAIL"
    
    # Ask about GPG signing
    read -p "Do you want to set up GPG commit signing? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_gpg "$GIT_NAME" "$GIT_EMAIL"
    fi
}

# === FUNCTION: Initialize Git repo ===
initialize_git_repo() {
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        echo "🚀 Initializing Git repository..."
        mkdir -p "$DOTFILES_DIR"
        cd "$DOTFILES_DIR"
        git init
        
        # Create initial files if they don't exist
        mkdir -p .config/{git,nvim}
        touch .bashrc .bash_aliases .tmux.conf .config/starship.toml
        
        # Create a basic README
        cat > README.md << 'EOF'
# My Dotfiles

This repository contains my personal dotfiles and configuration.

## Installation

Run the setup script:
```bash
./setup.sh
```

## Contents

- `.bashrc` - Bash configuration
- `.bash_aliases` - Custom aliases
- `.tmux.conf` - Tmux configuration
- `.config/nvim/` - Neovim configuration
- `.config/git/` - Git configuration
- `.config/starship.toml` - Starship prompt configuration
EOF
        
        git add .
        git commit -m "Initial dotfiles setup"
        
        echo "📋 Next steps for GitHub:"
        echo "1. Go to https://github.com/new"
        echo "2. Create a new repository named 'dotfiles'"
        echo "3. Don't initialize with README, .gitignore, or license"
        echo "4. Run these commands:"
        echo "   git remote add origin git@github.com:YOUR_USERNAME/dotfiles.git"
        echo "   git branch -M main"
        echo "   git push -u origin main"
        echo ""
        read -p "Press Enter when you've created the GitHub repository..."
        
        read -p "Enter your GitHub username: " GITHUB_USER
        git remote add origin "git@github.com:$GITHUB_USER/dotfiles.git"
        git branch -M main
        
        echo "🚀 Attempting to push to GitHub..."
        if git push -u origin main; then
            echo "✅ Successfully pushed to GitHub!"
        else
            echo "❌ Push failed. You may need to set up SSH keys or use HTTPS."
            echo "For SSH keys, visit: https://docs.github.com/en/authentication/connecting-to-github-with-ssh"
            echo "Or use HTTPS: git remote set-url origin https://github.com/$GITHUB_USER/dotfiles.git"
        fi
    else
        echo "✅ Git repository already exists"
        cd "$DOTFILES_DIR"
        git pull 2>/dev/null || echo "⚠️  Couldn't pull from remote (this is normal for new repos)"
    fi
}

# === FUNCTION: Safe symlink ===
safe_link() {
    local src="$1"
    local dest="$2"
    
    if [ ! -e "$src" ]; then
        echo "⏭️  Skipping missing source: $src"
        return
    fi
    
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        echo "🔁 Already linked: $dest"
        return
    fi
    
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        echo "🧪 Backing up existing file: $dest"
        mv "$dest" "$dest.bak.$(date +%s)"
    fi
    
    ln -sf "$src" "$dest"
    echo "🔗 Linked: $dest → $src"
}

# === FUNCTION: Symlink config files ===
symlink_configs() {
    echo "🔗 Creating symlinks..."
    
    mkdir -p "$CONFIG_TARGET"
    
    # Only symlink files that exist
    safe_link "$DOTFILES_DIR/.config/git" "$CONFIG_TARGET/git"
    safe_link "$DOTFILES_DIR/.config/nvim" "$CONFIG_TARGET/nvim"
    safe_link "$DOTFILES_DIR/.config/starship.toml" "$CONFIG_TARGET/starship.toml"
    safe_link "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
    safe_link "$DOTFILES_DIR/.bash_aliases" "$HOME/.bash_aliases"
    safe_link "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"
    
    echo "✅ Symlinks complete."
}

# === FUNCTION: Setup GPG signing ===
setup_gpg() {
    local git_name="$1"
    local git_email="$2"
    
    echo "🔐 Configuring GPG commit signing..."
    
    # Create GPG directory if it doesn't exist
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg
    
    if ! gpg --list-secret-keys --keyid-format=long | grep -q "$git_email"; then
        echo "🛠️  Generating new GPG key..."
        mkdir -p "$SCRIPTS_DIR"
        
        cat > "$SCRIPTS_DIR/key_input" <<EOF
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: $git_name
Name-Email: $git_email
Expire-Date: 0
%commit
EOF
        
        gpg --batch --generate-key "$SCRIPTS_DIR/key_input"
        rm "$SCRIPTS_DIR/key_input"
        echo "✅ GPG key generated."
    else
        echo "✅ GPG key already exists."
    fi
    
    KEYID=$(gpg --list-secret-keys --keyid-format=long "$git_email" | grep 'sec' | awk -F'/' '{print $2}' | awk '{print $1}')
    git config --global user.signingkey "$KEYID"
    git config --global commit.gpgsign true
    
    # Configure GPG
    echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf
    echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
    gpgconf --kill gpg-agent 2>/dev/null || true
    gpgconf --launch gpg-agent
    
    echo "📤 Your GPG public key (copy this to GitHub > Settings > GPG Keys):"
    echo "https://github.com/settings/keys"
    echo ""
    gpg --armor --export "$KEYID"
    echo ""
    read -p "Press Enter after you've added the GPG key to GitHub..."
}

# === MAIN ===
echo "🚀 Starting dotfiles setup..."

# Detect OS first
detect_os

# Install packages
install_packages

# Setup Git
setup_git

# Initialize Git repo and handle GitHub setup
initialize_git_repo

# Create symlinks
symlink_configs

echo "🎉 Dotfiles setup complete!"
echo "📋 Next steps:"
echo "1. Launch a new shell or run 'source ~/.bashrc' to apply changes"
echo "2. Configure your dotfiles in $DOTFILES_DIR"
echo "3. Commit and push changes: cd $DOTFILES_DIR && git add . && git commit -m 'Update config' && git push"
