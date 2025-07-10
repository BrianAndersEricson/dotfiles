#!/bin/bash
set -e

# === CONFIGURATION ===
DOTFILES_DIR="$HOME/.src/dotfiles"
CONFIG_TARGET="$HOME/.config"
SCRIPTS_DIR="$DOTFILES_DIR/scripts"

# === FUNCTION: Check for quit ===
check_quit() {
    local input="$1"
    if [[ "$input" =~ ^[Qq]$ ]] || [[ "$input" =~ ^[Qq][Uu][Ii][Tt]$ ]]; then
        echo "👋 Exiting setup. No changes were made."
        exit 0
    fi
}

# === FUNCTION: Setup menu ===
setup_menu() {
    echo "🚀 Dotfiles Setup Configuration"
    echo "================================"
    echo "What would you like to set up?"
    echo ""
    echo "1. 📦 Install packages (essential tools)"
    echo "2. 🔧 Configure Git (name, email, GPG signing)"
    echo "3. 🔑 Set up SSH key for GitHub"
    echo "4. 📂 Initialize/setup dotfiles repository"
    echo "5. 🔍 Import existing configurations"
    echo "6. 🔗 Create symlinks"
    echo "7. 🌟 Complete setup (all of the above)"
    echo "q. 🚪 Quit"
    echo ""
    read -p "Enter your choices (e.g., 1,3,5 or 7 for all, q to quit): " SETUP_CHOICES
    echo ""
    
    check_quit "$SETUP_CHOICES"
    
    # Parse choices
    INSTALL_PACKAGES=false
    SETUP_GIT=false
    SETUP_SSH=false
    SETUP_REPO=false
    IMPORT_CONFIGS=false
    CREATE_SYMLINKS=false
    
    if [[ "$SETUP_CHOICES" == *"7"* ]]; then
        INSTALL_PACKAGES=true
        SETUP_GIT=true
        SETUP_SSH=true
        SETUP_REPO=true
        IMPORT_CONFIGS=true
        CREATE_SYMLINKS=true
    else
        [[ "$SETUP_CHOICES" == *"1"* ]] && INSTALL_PACKAGES=true
        [[ "$SETUP_CHOICES" == *"2"* ]] && SETUP_GIT=true
        [[ "$SETUP_CHOICES" == *"3"* ]] && SETUP_SSH=true
        [[ "$SETUP_CHOICES" == *"4"* ]] && SETUP_REPO=true
        [[ "$SETUP_CHOICES" == *"5"* ]] && IMPORT_CONFIGS=true
        [[ "$SETUP_CHOICES" == *"6"* ]] && CREATE_SYMLINKS=true
    fi
}

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
        read -p "Do you want to reconfigure? (y/N/q to quit): " -n 1 -r
        echo
        check_quit "$REPLY"
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # Prompt for git configuration
    read -p "Enter your Git name (q to quit): " GIT_NAME
    check_quit "$GIT_NAME"
    read -p "Enter your Git email (q to quit): " GIT_EMAIL
    check_quit "$GIT_EMAIL"
    
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    
    echo "✅ Git configured with:"
    echo "   Name: $GIT_NAME"
    echo "   Email: $GIT_EMAIL"
    
    # Ask about GPG signing
    read -p "Do you want to set up GPG commit signing? (y/N/q to quit): " -n 1 -r
    echo
    check_quit "$REPLY"
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_gpg "$GIT_NAME" "$GIT_EMAIL"
    fi
}

# === FUNCTION: Setup SSH key ===
setup_ssh_key() {
    echo "🔑 Setting up SSH key for GitHub..."
    
    SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
    
    if [ -f "$SSH_KEY_PATH" ]; then
        echo "✅ SSH key already exists at $SSH_KEY_PATH"
        echo "📋 Your public key (copy this to GitHub > Settings > SSH Keys):"
        echo "https://github.com/settings/keys"
        echo ""
        cat "$SSH_KEY_PATH.pub"
        echo ""
        read -p "Press Enter after you've added the SSH key to GitHub (or 'q' to quit)... " CONTINUE_SSH
        check_quit "$CONTINUE_SSH"
        return
    fi
    
    # Get email for SSH key
    if git config --global user.email >/dev/null 2>&1; then
        GIT_EMAIL=$(git config --global user.email)
        echo "Using Git email: $GIT_EMAIL"
        read -p "Press Enter to continue or 'q' to quit: " CONTINUE_CHOICE
        check_quit "$CONTINUE_CHOICE"
    else
        read -p "Enter your email for the SSH key (q to quit): " GIT_EMAIL
        check_quit "$GIT_EMAIL"
    fi
    
    echo "🔐 Generating SSH key..."
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY_PATH" -N ""
    
    # Start SSH agent and add key
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add "$SSH_KEY_PATH" >/dev/null 2>&1
    
    echo "✅ SSH key generated!"
    echo ""
    echo "📋 Your public key (copy this to GitHub > Settings > SSH Keys):"
    echo "https://github.com/settings/keys"
    echo ""
    cat "$SSH_KEY_PATH.pub"
    echo ""
    read -p "Press Enter after you've added the SSH key to GitHub (or 'q' to quit)... " CONTINUE_SSH
    check_quit "$CONTINUE_SSH"
    
    # Test SSH connection
    echo "🧪 Testing SSH connection to GitHub..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        echo "✅ SSH connection to GitHub successful!"
    else
        echo "⚠️  SSH test failed, but this might be normal. Try the connection later."
    fi
}

# === FUNCTION: Discover and import existing configs ===
discover_and_import_configs() {
    echo "🔍 Discovering existing configuration files..."
    
    # Define config locations to check
    declare -A CONFIG_LOCATIONS=(
        ["$HOME/.bashrc"]="$DOTFILES_DIR/.bashrc"
        ["$HOME/.bash_aliases"]="$DOTFILES_DIR/.bash_aliases"
        ["$HOME/.bash_profile"]="$DOTFILES_DIR/.bash_profile"
        ["$HOME/.profile"]="$DOTFILES_DIR/.profile"
        ["$HOME/.tmux.conf"]="$DOTFILES_DIR/.tmux.conf"
        ["$HOME/.vimrc"]="$DOTFILES_DIR/.vimrc"
        ["$HOME/.zshrc"]="$DOTFILES_DIR/.zshrc"
        ["$HOME/.gitconfig"]="$DOTFILES_DIR/.gitconfig"
        ["$CONFIG_TARGET/starship.toml"]="$DOTFILES_DIR/.config/starship.toml"
        ["$CONFIG_TARGET/nvim"]="$DOTFILES_DIR/.config/nvim"
        ["$CONFIG_TARGET/git"]="$DOTFILES_DIR/.config/git"
        ["$CONFIG_TARGET/tmux"]="$DOTFILES_DIR/.config/tmux"
        ["$CONFIG_TARGET/alacritty"]="$DOTFILES_DIR/.config/alacritty"
        ["$CONFIG_TARGET/kitty"]="$DOTFILES_DIR/.config/kitty"
        ["$CONFIG_TARGET/wezterm"]="$DOTFILES_DIR/.config/wezterm"
        ["$CONFIG_TARGET/fish"]="$DOTFILES_DIR/.config/fish"
        ["$CONFIG_TARGET/zsh"]="$DOTFILES_DIR/.config/zsh"
    )
    
    found_configs=()
    
    # Check each location for non-empty configs
    for source_path in "${!CONFIG_LOCATIONS[@]}"; do
        dest_path="${CONFIG_LOCATIONS[$source_path]}"
        
        if [ -f "$source_path" ] && [ -s "$source_path" ]; then
            # It's a non-empty file
            if [ ! -e "$dest_path" ]; then
                found_configs+=("$source_path|$dest_path|file")
            fi
        elif [ -d "$source_path" ] && [ "$(ls -A "$source_path" 2>/dev/null)" ]; then
            # It's a non-empty directory
            if [ ! -e "$dest_path" ]; then
                found_configs+=("$source_path|$dest_path|dir")
            fi
        fi
    done
    
    if [ ${#found_configs[@]} -eq 0 ]; then
        echo "✅ No existing configurations found to import."
        return
    fi
    
    echo "📋 Found ${#found_configs[@]} existing configuration(s):"
    for i in "${!found_configs[@]}"; do
        IFS='|' read -r source dest type <<< "${found_configs[$i]}"
        if [ "$type" = "file" ]; then
            size=$(wc -l < "$source" 2>/dev/null || echo "?")
            echo "   $((i+1)). $source ($size lines)"
        else
            count=$(find "$source" -type f 2>/dev/null | wc -l)
            echo "   $((i+1)). $source/ ($count files)"
        fi
    done
    echo ""
    
    read -p "Enter numbers to import (e.g., 1,3,4 or 'all' for everything, 'q' to quit): " IMPORT_CHOICE
    echo ""
    
    check_quit "$IMPORT_CHOICE"
    
    if [ "$IMPORT_CHOICE" = "all" ]; then
        SELECTED_CONFIGS=("${found_configs[@]}")
    else
        SELECTED_CONFIGS=()
        IFS=',' read -ra CHOICES <<< "$IMPORT_CHOICE"
        for choice in "${CHOICES[@]}"; do
            choice=$(echo "$choice" | tr -d ' ')  # Remove spaces
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#found_configs[@]} ]; then
                SELECTED_CONFIGS+=("${found_configs[$((choice-1))]}")
            fi
        done
    fi
    
    if [ ${#SELECTED_CONFIGS[@]} -eq 0 ]; then
        echo "⏭️  No configurations selected for import."
        return
    fi
    
    echo "📥 Importing ${#SELECTED_CONFIGS[@]} selected configuration(s)..."
    mkdir -p "$DOTFILES_DIR/.config"
    
    for config in "${SELECTED_CONFIGS[@]}"; do
        IFS='|' read -r source dest type <<< "$config"
        
        # Create destination directory
        dest_dir=$(dirname "$dest")
        mkdir -p "$dest_dir"
        
        if [ "$type" = "file" ]; then
            echo "📄 Importing: $source → $dest"
            cp "$source" "$dest"
        else
            echo "📁 Importing: $source/ → $dest/"
            cp -r "$source" "$dest"
        fi
    done
    
    echo "✅ Configuration import complete!"
    echo ""
}

# === FUNCTION: Initialize Git repo ===
initialize_git_repo() {
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        echo "🚀 Initializing Git repository..."
        mkdir -p "$DOTFILES_DIR"
        cd "$DOTFILES_DIR"
        git init
        
        # Create initial directory structure
        mkdir -p .config/{git,nvim}
        
        # Import existing configs first
        discover_and_import_configs
        
        # Create any missing basic files (only if they don't exist)
        [ ! -f "$DOTFILES_DIR/.bashrc" ] && touch "$DOTFILES_DIR/.bashrc"
        [ ! -f "$DOTFILES_DIR/.bash_aliases" ] && touch "$DOTFILES_DIR/.bash_aliases"
        [ ! -f "$DOTFILES_DIR/.tmux.conf" ] && touch "$DOTFILES_DIR/.tmux.conf"
        [ ! -f "$DOTFILES_DIR/.config/starship.toml" ] && touch "$DOTFILES_DIR/.config/starship.toml"
        
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
        
        echo "📋 GitHub repository setup:"
        echo "1. Go to https://github.com/new"
        echo "2. Create a new repository named 'dotfiles'"
        echo "3. Don't initialize with README, .gitignore, or license"
        echo "4. Leave it empty - we'll push our existing code"
        echo ""
        read -p "Press Enter when you've created the GitHub repository (or 'q' to quit)... " GITHUB_CONTINUE
        check_quit "$GITHUB_CONTINUE"
        
        read -p "Enter your GitHub username (q to quit): " GITHUB_USER
        check_quit "$GITHUB_USER"
        
        # Ask about SSH vs HTTPS
        echo ""
        echo "Choose connection method:"
        echo "1. SSH (recommended - uses the SSH key we set up)"
        echo "2. HTTPS (will prompt for username/token)"
        echo "q. Quit"
        read -p "Enter choice (1, 2, or q): " CONNECTION_CHOICE
        check_quit "$CONNECTION_CHOICE"
        
        if [ "$CONNECTION_CHOICE" = "1" ]; then
            git remote add origin "git@github.com:$GITHUB_USER/dotfiles.git"
            REMOTE_URL="git@github.com:$GITHUB_USER/dotfiles.git"
        else
            git remote add origin "https://github.com/$GITHUB_USER/dotfiles.git"
            REMOTE_URL="https://github.com/$GITHUB_USER/dotfiles.git"
        fi
        
        git branch -M main
        
        echo "🚀 Attempting to push to GitHub..."
        if git push -u origin main; then
            echo "✅ Successfully pushed to GitHub!"
            echo "🌐 Your repository: https://github.com/$GITHUB_USER/dotfiles"
        else
            echo "❌ Push failed."
            echo ""
            echo "💡 To fix this later, run these commands:"
            echo "   cd $DOTFILES_DIR"
            if [ "$CONNECTION_CHOICE" = "1" ]; then
                echo "   # If you need to set up SSH keys:"
                echo "   # Visit: https://docs.github.com/en/authentication/connecting-to-github-with-ssh"
                echo "   # Or switch to HTTPS:"
                echo "   git remote set-url origin https://github.com/$GITHUB_USER/dotfiles.git"
            fi
            echo "   git push -u origin main"
            echo ""
            echo "⚠️  Continuing with local setup..."
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
    
    # Define all possible symlinks
    declare -A SYMLINKS=(
        ["$DOTFILES_DIR/.bashrc"]="$HOME/.bashrc"
        ["$DOTFILES_DIR/.bash_aliases"]="$HOME/.bash_aliases"
        ["$DOTFILES_DIR/.bash_profile"]="$HOME/.bash_profile"
        ["$DOTFILES_DIR/.profile"]="$HOME/.profile"
        ["$DOTFILES_DIR/.tmux.conf"]="$HOME/.tmux.conf"
        ["$DOTFILES_DIR/.vimrc"]="$HOME/.vimrc"
        ["$DOTFILES_DIR/.zshrc"]="$HOME/.zshrc"
        ["$DOTFILES_DIR/.gitconfig"]="$HOME/.gitconfig"
        ["$DOTFILES_DIR/.config/starship.toml"]="$CONFIG_TARGET/starship.toml"
        ["$DOTFILES_DIR/.config/nvim"]="$CONFIG_TARGET/nvim"
        ["$DOTFILES_DIR/.config/git"]="$CONFIG_TARGET/git"
        ["$DOTFILES_DIR/.config/tmux"]="$CONFIG_TARGET/tmux"
        ["$DOTFILES_DIR/.config/alacritty"]="$CONFIG_TARGET/alacritty"
        ["$DOTFILES_DIR/.config/kitty"]="$CONFIG_TARGET/kitty"
        ["$DOTFILES_DIR/.config/wezterm"]="$CONFIG_TARGET/wezterm"
        ["$DOTFILES_DIR/.config/fish"]="$CONFIG_TARGET/fish"
        ["$DOTFILES_DIR/.config/zsh"]="$CONFIG_TARGET/zsh"
    )
    
    # Only symlink files/directories that exist in the dotfiles directory
    for source in "${!SYMLINKS[@]}"; do
        dest="${SYMLINKS[$source]}"
        safe_link "$source" "$dest"
    done
    
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
    read -p "Press Enter after you've added the GPG key to GitHub (or 'q' to quit)... " GPG_CONTINUE
    check_quit "$GPG_CONTINUE"
}

# === MAIN ===
echo "🚀 Starting dotfiles setup..."

# Show setup menu
setup_menu

# Detect OS first  
detect_os

# Execute selected components
if [ "$INSTALL_PACKAGES" = true ]; then
    install_packages
fi

if [ "$SETUP_GIT" = true ]; then
    setup_git
fi

if [ "$SETUP_SSH" = true ]; then
    setup_ssh_key
fi

if [ "$SETUP_REPO" = true ]; then
    initialize_git_repo
fi

if [ "$IMPORT_CONFIGS" = true ]; then
    discover_and_import_configs
fi

if [ "$CREATE_SYMLINKS" = true ]; then
    symlink_configs
fi

echo "🎉 Dotfiles setup complete!"
echo "📋 Next steps:"
echo "1. Launch a new shell or run 'source ~/.bashrc' to apply changes"
echo "2. Configure your dotfiles in $DOTFILES_DIR"
echo "3. Commit and push changes: cd $DOTFILES_DIR && git add . && git commit -m 'Update config' && git push"
