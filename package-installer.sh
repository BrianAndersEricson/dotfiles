#!/bin/bash
# Smart Package Installer Script
# Version: 1.0.0
# Supports: Ubuntu/Debian and Arch Linux
# Installs categorized development tools with latest versions

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly LOG_FILE="/tmp/package-installer-$(date +%Y%m%d-%H%M%S).log"
readonly TEMP_DIR="/tmp/package-installer-temp"

# Global variables
OS=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""
AUR_HELPER=""
INSTALLED_PACKAGES=()

# Helper functions
print_colored() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

print_header() {
    echo
    print_colored "$CYAN" "═══════════════════════════════════════════════════════════════"
    print_colored "$CYAN" "$1"
    print_colored "$CYAN" "═══════════════════════════════════════════════════════════════"
    echo
}

print_success() { print_colored "$GREEN" "✅ $*"; }
print_error() { print_colored "$RED" "❌ $*"; }
print_warning() { print_colored "$YELLOW" "⚠️  $*"; }
print_info() { print_colored "$BLUE" "ℹ️  $*"; }
print_step() { print_colored "$PURPLE" "👉 $*"; }

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

confirm() {
    local prompt="${1:-Continue?}"
    read -p "$prompt [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

pause_for_user() {
    echo
    read -p "Press Enter to continue... "
    echo
}

# Detect OS and setup package manager
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "${ID,,}" in
            ubuntu|debian|pop|linuxmint)
                OS="debian"
                PACKAGE_MANAGER="apt"
                UPDATE_CMD="sudo apt update"
                INSTALL_CMD="sudo apt install -y"
                ;;
            arch|manjaro|endeavouros)
                OS="arch"
                PACKAGE_MANAGER="pacman"
                UPDATE_CMD="sudo pacman -Sy"
                INSTALL_CMD="sudo pacman -S --needed --noconfirm"
                ;;
            *)
                print_error "Unsupported OS: $ID"
                exit 1
                ;;
        esac
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    
    print_info "Detected OS: $OS"
    log "Detected OS: $OS"
}

# Update package manager
update_packages() {
    print_step "Updating package database..."
    if $UPDATE_CMD &>/dev/null; then
        print_success "Package database updated"
    else
        print_warning "Failed to update package database"
    fi
}

# Install a package
install_package() {
    local package="$1"
    print_step "Installing: $package"
    
    if $INSTALL_CMD "$package" &>/dev/null; then
        print_success "Installed: $package"
        log "Installed: $package"
        INSTALLED_PACKAGES+=("$package")
        return 0
    else
        print_error "Failed to install: $package"
        log "Failed to install: $package"
        return 1
    fi
}

# Install AUR helper for Arch
install_aur_helper() {
    if [[ "$OS" != "arch" ]]; then
        return 0
    fi
    
    # Check if AUR helper already exists
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        print_success "Yay is already installed"
        return 0
    elif command -v paru &>/dev/null; then
        AUR_HELPER="paru"
        print_success "Paru is already installed"
        return 0
    fi
    
    print_header "Installing Yay (AUR Helper)"
    
    # Install dependencies
    install_package "base-devel"
    install_package "git"
    
    # Clone and build yay
    local yay_dir="$TEMP_DIR/yay"
    rm -rf "$yay_dir"
    
    print_step "Cloning yay repository..."
    if git clone https://aur.archlinux.org/yay.git "$yay_dir" &>/dev/null; then
        cd "$yay_dir"
        print_step "Building yay..."
        if makepkg -si --noconfirm &>/dev/null; then
            print_success "Yay installed successfully!"
            AUR_HELPER="yay"
            INSTALLED_PACKAGES+=("yay (AUR)")
            cd - &>/dev/null
            rm -rf "$yay_dir"
            return 0
        fi
    fi
    
    print_error "Failed to install yay"
    return 1
}

# Install from AUR
install_aur_package() {
    local package="$1"
    
    if [[ "$OS" != "arch" ]] || [[ -z "$AUR_HELPER" ]]; then
        return 1
    fi
    
    print_step "Installing from AUR: $package"
    
    if $AUR_HELPER -S --needed --noconfirm "$package" &>/dev/null; then
        print_success "Installed from AUR: $package"
        log "Installed from AUR: $package"
        INSTALLED_PACKAGES+=("$package (AUR)")
        return 0
    else
        print_error "Failed to install from AUR: $package"
        log "Failed to install from AUR: $package"
        return 1
    fi
}

# Install Neovim (latest from GitHub)
install_neovim() {
    print_header "Installing Neovim (Latest Version)"
    
    # Check current version - handle the case where nvim exists but can't run
    local current_version="not_installed"
    if command -v nvim &>/dev/null; then
        # Try to get version, but don't fail if nvim is broken
        current_version=$(nvim --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "error")
        if [[ "$current_version" == "error" ]]; then
            print_warning "Neovim is installed but not working properly"
            current_version="not_installed"
        else
            print_info "Current version: $current_version"
        fi
    fi
    
    # Get latest version
    print_step "Checking latest version..."
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    
    if [[ -z "$latest_version" ]]; then
        print_error "Could not fetch latest version"
        return 1
    fi
    
    print_info "Latest version: $latest_version"
    
    if [[ "$current_version" == "$latest_version" ]]; then
        print_success "Neovim is already up to date!"
        return 0
    fi
    
    case "$OS" in
        debian)
            # For Ubuntu/Debian, we have multiple options
            print_info "Choose installation method for Neovim $latest_version:"
            echo "  1) Tarball (recommended - latest version, fast)"
            echo "  2) AppImage (portable, may require FUSE)"
            echo "  3) PPA (system integration, automatic updates)"
            echo "  4) Build from source (latest features)"
            echo
            read -p "Enter choice [1-4]: " nvim_choice
            
            case "$nvim_choice" in
                1)
                    # Tarball method - recommended
                    print_step "Installing Neovim via tarball..."
                    local temp_dir="$TEMP_DIR/neovim"
                    mkdir -p "$temp_dir"
                    
                    # Use the correct tarball URL for x86_64
                    local download_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
                    
                    print_step "Downloading Neovim $latest_version..."
                    if curl -Lo "$temp_dir/nvim-linux-x86_64.tar.gz" "$download_url" && [[ -s "$temp_dir/nvim-linux-x86_64.tar.gz" ]]; then
                        cd "$temp_dir"
                        
                        # Extract the tarball
                        if tar xzf nvim-linux-x86_64.tar.gz; then
                            # Find the extracted directory (it should be nvim-linux-x86_64)
                            local nvim_dir=$(find . -maxdepth 1 -type d -name "nvim-*" | head -n1)
                            
                            if [[ -n "$nvim_dir" && -d "$nvim_dir" ]]; then
                                # Remove old installation if exists
                                [[ -d "$HOME/.local/nvim" ]] && rm -rf "$HOME/.local/nvim"
                                
                                # Copy to local directory
                                mkdir -p "$HOME/.local"
                                cp -r "$nvim_dir" "$HOME/.local/nvim"
                                
                                # Create symlink in bin
                                mkdir -p "$HOME/.local/bin"
                                ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
                                
                                cd - &>/dev/null
                                rm -rf "$temp_dir"
                                
                                print_success "Neovim $latest_version installed to $HOME/.local/bin/nvim"
                                INSTALLED_PACKAGES+=("neovim $latest_version (tarball)")
                            else
                                print_error "Failed to find extracted Neovim directory"
                                return 1
                            fi
                        else
                            print_error "Failed to extract tarball"
                            return 1
                        fi
                    else
                        print_error "Failed to download Neovim tarball"
                        return 1
                    fi
                    ;;
                    
                2)
                    # AppImage method
                    print_step "Installing Neovim via AppImage..."
                    local nvim_path="$HOME/.local/bin/nvim"
                    mkdir -p "$HOME/.local/bin"
                    
                    local download_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
                    
                    if curl -Lo "$nvim_path" "$download_url" && [[ -s "$nvim_path" ]]; then
                        chmod u+x "$nvim_path"
                        print_success "Neovim $latest_version installed to $nvim_path"
                        INSTALLED_PACKAGES+=("neovim $latest_version (AppImage)")
                        print_warning "Note: AppImage requires FUSE. If it doesn't work, try the tarball method."
                    else
                        print_error "Failed to download Neovim AppImage"
                        return 1
                    fi
                    ;;
                    
                3)
                    # PPA method
                    print_step "Installing Neovim via PPA..."
                    
                    # Add PPA
                    print_step "Adding Neovim PPA..."
                    if ! grep -q "neovim-ppa" /etc/apt/sources.list.d/*.list 2>/dev/null; then
                        sudo add-apt-repository ppa:neovim-ppa/unstable -y
                        sudo apt update
                    fi
                    
                    # Install from PPA
                    if install_package "neovim"; then
                        local installed_version=$(nvim --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")
                        INSTALLED_PACKAGES+=("neovim $installed_version (PPA)")
                    else
                        print_error "Failed to install Neovim from PPA"
                        return 1
                    fi
                    ;;
                    
                4)
                    # Build from source
                    print_step "Building Neovim from source..."
                    
                    # Install build dependencies
                    print_step "Installing build dependencies..."
                    local build_deps="ninja-build gettext cmake unzip curl build-essential"
                    for dep in $build_deps; do
                        install_package "$dep"
                    done
                    
                    # Clone and build
                    local build_dir="$TEMP_DIR/neovim-build"
                    rm -rf "$build_dir"
                    
                    print_step "Cloning Neovim repository..."
                    if git clone https://github.com/neovim/neovim.git "$build_dir"; then
                        cd "$build_dir"
                        git checkout "$(git describe --tags --abbrev=0)"
                        
                        print_step "Building Neovim (this may take a while)..."
                        if make CMAKE_BUILD_TYPE=Release; then
                            print_step "Installing Neovim..."
                            if sudo make install; then
                                cd - &>/dev/null
                                rm -rf "$build_dir"
                                print_success "Neovim $latest_version built and installed"
                                INSTALLED_PACKAGES+=("neovim $latest_version (source)")
                            else
                                print_error "Failed to install Neovim"
                                return 1
                            fi
                        else
                            print_error "Failed to build Neovim"
                            return 1
                        fi
                    else
                        print_error "Failed to clone Neovim repository"
                        return 1
                    fi
                    ;;
                    
                *)
                    print_warning "Invalid choice, skipping Neovim installation"
                    return 1
                    ;;
            esac
            ;;
            
        arch)
            # For Arch, use AUR for latest version
            if [[ -n "$AUR_HELPER" ]]; then
                print_step "Installing Neovim from AUR (neovim-git)..."
                install_aur_package "neovim-git"
                return $?
            else
                # Fallback to official repo which is usually very recent
                print_step "Installing Neovim from official repository..."
                if install_package "neovim"; then
                    local installed_version=$(nvim --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")
                    print_info "Installed version: $installed_version"
                    
                    # Check if it's recent enough
                    if [[ "$installed_version" < "v0.11" ]]; then
                        print_warning "Repository version is older than 0.11. Consider installing an AUR helper for neovim-git."
                    fi
                else
                    print_error "Failed to install Neovim"
                    return 1
                fi
            fi
            ;;
    esac
}

# Install Starship prompt
install_starship() {
    print_header "Installing Starship Prompt"
    
    if command -v starship &>/dev/null; then
        local current_version
        current_version=$(starship --version | awk '{print $2}')
        print_info "Starship is already installed (version $current_version)"
        
        ! confirm "Reinstall/update Starship?" && return 0
    fi
    
    print_step "Installing Starship..."
    
    if curl -sS https://starship.rs/install.sh | sh -s -- -y &>/dev/null; then
        print_success "Starship installed successfully!"
        INSTALLED_PACKAGES+=("starship")
    else
        print_error "Failed to install Starship"
        return 1
    fi
}

# Package definitions by category
declare -A PACKAGES_ESSENTIAL=(
    [debian]="build-essential curl wget git openssh-client gnupg"
    [arch]="base-devel curl wget git openssh gnupg"
)

declare -A PACKAGES_SHELL_TOOLS=(
    [debian]="tmux zsh fish bash-completion command-not-found"
    [arch]="tmux zsh fish bash-completion pkgfile"
)

declare -A PACKAGES_MODERN_CLI=(
    [debian]="fzf ripgrep fd-find bat silversearcher-ag jq tree htop ncdu duf"
    [arch]="fzf ripgrep fd bat the_silver_searcher jq tree htop ncdu duf"
)

declare -A PACKAGES_PYTHON=(
    [debian]="python3 python3-pip python3-venv python3-dev pipx"
    [arch]="python python-pip python-pipx python-virtualenv"
)

declare -A PACKAGES_NODE=(
    [debian]="nodejs npm"
    [arch]="nodejs npm"
)

declare -A PACKAGES_RUST=(
    [debian]="cargo rustc"
    [arch]="rust"
)

declare -A PACKAGES_GO=(
    [debian]="golang-go"
    [arch]="go"
)

declare -A PACKAGES_CONTAINERS=(
    [debian]="docker.io docker-compose podman"
    [arch]="docker docker-compose podman"
)

declare -A PACKAGES_DEVELOPMENT=(
    [debian]="make cmake gcc g++ clang llvm gdb valgrind pkg-config autoconf automake libtool"
    [arch]="make cmake gcc clang llvm gdb valgrind pkg-config autoconf automake libtool"
)

# Special tools that need custom installation
declare -A SPECIAL_TOOLS=(
    ["zoxide"]="Modern cd replacement with smart jumps"
    ["exa"]="Modern ls replacement (now eza)"
    ["tldr"]="Simplified man pages"
    ["lazygit"]="Terminal UI for git"
    ["delta"]="Better git diff"
    ["mcfly"]="Smart shell history"
    ["navi"]="Interactive cheatsheet tool"
    ["broot"]="Better tree navigation"
    ["bottom"]="Modern top replacement"
)

# Install special tools
install_special_tool() {
    local tool="$1"
    
    case "$tool" in
        zoxide)
            print_step "Installing zoxide..."
            if [[ "$OS" == "debian" ]]; then
                curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash &>/dev/null
                INSTALLED_PACKAGES+=("zoxide")
            else
                install_package "zoxide"
            fi
            ;;
            
        exa|eza)
            print_step "Installing eza (exa replacement)..."
            if [[ "$OS" == "debian" ]]; then
                # Install from cargo
                if command -v cargo &>/dev/null; then
                    cargo install eza &>/dev/null
                    INSTALLED_PACKAGES+=("eza (cargo)")
                else
                    print_warning "Need cargo to install eza. Install Rust first."
                fi
            else
                install_package "eza"
            fi
            ;;
            
        tldr)
            print_step "Installing tldr..."
            if command -v npm &>/dev/null; then
                sudo npm install -g tldr &>/dev/null
                INSTALLED_PACKAGES+=("tldr (npm)")
            elif command -v pip3 &>/dev/null; then
                pip3 install --user tldr &>/dev/null
                INSTALLED_PACKAGES+=("tldr (pip)")
            else
                print_warning "Need npm or pip to install tldr"
            fi
            ;;
            
        lazygit)
            print_step "Installing lazygit..."
            if [[ "$OS" == "debian" ]]; then
                local lazygit_version
                lazygit_version=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep tag_name | cut -d'"' -f4)
                curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${lazygit_version#v}_Linux_x86_64.tar.gz" &>/dev/null
                tar xf lazygit.tar.gz lazygit
                sudo install lazygit /usr/local/bin
                rm -f lazygit.tar.gz lazygit
                INSTALLED_PACKAGES+=("lazygit $lazygit_version")
            else
                install_package "lazygit"
            fi
            ;;
            
        delta)
            print_step "Installing delta..."
            if [[ "$OS" == "debian" ]]; then
                local delta_version
                delta_version=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | grep tag_name | cut -d'"' -f4)
                curl -Lo delta.deb "https://github.com/dandavison/delta/releases/latest/download/git-delta_${delta_version#v}_amd64.deb" &>/dev/null
                sudo dpkg -i delta.deb &>/dev/null
                rm -f delta.deb
                INSTALLED_PACKAGES+=("delta $delta_version")
            else
                install_package "git-delta"
            fi
            ;;
            
        mcfly)
            print_step "Installing mcfly..."
            if [[ "$OS" == "debian" ]]; then
                curl -LSfs https://raw.githubusercontent.com/cantino/mcfly/master/ci/install.sh | sh -s -- --git cantino/mcfly &>/dev/null
                INSTALLED_PACKAGES+=("mcfly")
            else
                if [[ -n "$AUR_HELPER" ]]; then
                    install_aur_package "mcfly"
                fi
            fi
            ;;
            
        navi)
            print_step "Installing navi..."
            if command -v cargo &>/dev/null; then
                cargo install navi &>/dev/null
                INSTALLED_PACKAGES+=("navi (cargo)")
            else
                print_warning "Need cargo to install navi. Install Rust first."
            fi
            ;;
            
        broot)
            print_step "Installing broot..."
            if command -v cargo &>/dev/null; then
                cargo install broot &>/dev/null
                INSTALLED_PACKAGES+=("broot (cargo)")
            else
                print_warning "Need cargo to install broot. Install Rust first."
            fi
            ;;
            
        bottom)
            print_step "Installing bottom..."
            if [[ "$OS" == "debian" ]]; then
                curl -LO https://github.com/ClementTsang/bottom/releases/download/0.9.6/bottom_0.9.6_amd64.deb &>/dev/null
                sudo dpkg -i bottom_0.9.6_amd64.deb &>/dev/null
                rm -f bottom_0.9.6_amd64.deb
                INSTALLED_PACKAGES+=("bottom 0.9.6")
            else
                install_package "bottom"
            fi
            ;;
    esac
    
    print_success "Installed: $tool"
}

# Show category menu
show_category_menu() {
    print_header "Package Categories"
    
    echo "Select categories to install:"
    echo
    echo "  1) 📦 Essential tools (build tools, git, curl, etc.)"
    echo "  2) 🐚 Shell tools (tmux, zsh, fish, completions)"
    echo "  3) 🚀 Modern CLI tools (fzf, ripgrep, bat, etc.)"
    echo "  4) 🐍 Python development"
    echo "  5) 📗 Node.js development"
    echo "  6) 🦀 Rust development"
    echo "  7) 🐹 Go development"
    echo "  8) 🐳 Containers (Docker, Podman)"
    echo "  9) 🔧 Development tools (compilers, debuggers)"
    echo "  10) ✨ Special tools (zoxide, eza, tldr, etc.)"
    echo "  11) 📝 Neovim (latest from GitHub)"
    echo "  12) 🌟 Starship prompt"
    echo "  13) 🏗️  Install everything"
    echo "  q) 🚪 Back to main menu"
    echo
    read -p "Enter choices (e.g., 1,3,5 or 13 for all): " choices
    echo
}

# Install selected categories
install_categories() {
    local choices="$1"
    
    # Install all if selected
    if [[ "$choices" == *"13"* ]]; then
        choices="1,2,3,4,5,6,7,8,9,10,11,12"
    fi
    
    # Process each choice
    IFS=',' read -ra choice_array <<< "$choices"
    for choice in "${choice_array[@]}"; do
        choice=$(echo "$choice" | tr -d ' ')
        
        case "$choice" in
            1)
                print_header "Installing Essential Tools"
                install_from_list "${PACKAGES_ESSENTIAL[$OS]}"
                ;;
            2)
                print_header "Installing Shell Tools"
                install_from_list "${PACKAGES_SHELL_TOOLS[$OS]}"
                ;;
            3)
                print_header "Installing Modern CLI Tools"
                install_from_list "${PACKAGES_MODERN_CLI[$OS]}"
                ;;
            4)
                print_header "Installing Python Development Tools"
                install_from_list "${PACKAGES_PYTHON[$OS]}"
                ;;
            5)
                print_header "Installing Node.js Development Tools"
                install_from_list "${PACKAGES_NODE[$OS]}"
                ;;
            6)
                print_header "Installing Rust Development Tools"
                if [[ "$OS" == "debian" ]]; then
                    if confirm "Install Rust via rustup (recommended)?"; then
                        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                        source "$HOME/.cargo/env"
                        INSTALLED_PACKAGES+=("rust (rustup)")
                    else
                        install_from_list "${PACKAGES_RUST[$OS]}"
                    fi
                else
                    install_from_list "${PACKAGES_RUST[$OS]}"
                fi
                ;;
            7)
                print_header "Installing Go Development Tools"
                install_from_list "${PACKAGES_GO[$OS]}"
                ;;
            8)
                print_header "Installing Container Tools"
                install_from_list "${PACKAGES_CONTAINERS[$OS]}"
                if [[ "$OS" == "debian" ]]; then
                    sudo usermod -aG docker "$USER" 2>/dev/null || true
                    print_info "Added $USER to docker group. Log out and back in for changes to take effect."
                fi
                ;;
            9)
                print_header "Installing Development Tools"
                install_from_list "${PACKAGES_DEVELOPMENT[$OS]}"
                ;;
            10)
                install_special_tools_menu
                ;;
            11)
                install_neovim
                ;;
            12)
                install_starship
                ;;
        esac
    done
}

# Install from a list of packages
install_from_list() {
    local packages="$1"
    local failed=()
    
    for package in $packages; do
        if ! install_package "$package"; then
            failed+=("$package")
        fi
    done
    
    if [[ ${#failed[@]} -gt 0 ]]; then
        print_warning "Failed to install: ${failed[*]}"
    fi
}

# Special tools menu
install_special_tools_menu() {
    print_header "Special Tools Installation"
    
    echo "Select tools to install:"
    echo
    
    local i=1
    local tool_keys=()
    for tool in "${!SPECIAL_TOOLS[@]}"; do
        printf "  %2d) %-12s - %s\n" "$i" "$tool" "${SPECIAL_TOOLS[$tool]}"
        tool_keys+=("$tool")
        ((i++))
    done
    
    echo "  a) Install all special tools"
    echo "  b) Back"
    echo
    
    read -p "Enter choices (e.g., 1,3,5 or a for all): " special_choices
    
    if [[ "$special_choices" == "a" ]]; then
        for tool in "${tool_keys[@]}"; do
            install_special_tool "$tool"
        done
    elif [[ "$special_choices" != "b" ]]; then
        IFS=',' read -ra choice_array <<< "$special_choices"
        for choice in "${choice_array[@]}"; do
            choice=$(echo "$choice" | tr -d ' ')
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -le "${#tool_keys[@]}" ]]; then
                install_special_tool "${tool_keys[$((choice-1))]}"
            fi
        done
    fi
}

# Print installation summary
print_summary() {
    print_header "Installation Summary"
    
    if [[ ${#INSTALLED_PACKAGES[@]} -eq 0 ]]; then
        print_info "No packages were installed."
    else
        print_success "Successfully installed ${#INSTALLED_PACKAGES[@]} packages:"
        echo
        for pkg in "${INSTALLED_PACKAGES[@]}"; do
            echo "  • $pkg"
        done
    fi
    
    echo
    print_info "Log file: $LOG_FILE"
}

# Main menu
show_main_menu() {
    clear
    print_colored "$CYAN" "╔════════════════════════════════════════════════════════════════╗"
    print_colored "$CYAN" "║            📦 Smart Package Installer v1.0.0                   ║"
    print_colored "$CYAN" "║                                                                ║"
    print_colored "$CYAN" "║  Install categorized development tools for Arch & Debian/Ubuntu║"
    print_colored "$CYAN" "╚════════════════════════════════════════════════════════════════╝"
    echo
    
    print_info "Detected: $OS system with $PACKAGE_MANAGER"
    if [[ "$OS" == "arch" ]] && [[ -n "$AUR_HELPER" ]]; then
        print_info "AUR Helper: $AUR_HELPER"
    fi
    echo
    
    echo "What would you like to do?"
    echo
    echo "  1) 📋 Install packages by category"
    echo "  2) 🏗️  Quick install (essentials + modern CLI + dev tools)"
    echo "  3) 🎯 Install Arch AUR helper (yay)"
    echo "  4) 🔄 Update system packages"
    echo "  q) 🚪 Quit"
    echo
    read -p "Enter your choice: " -n 1 main_choice
    echo
}

# Quick install option
quick_install() {
    print_header "Quick Install"
    
    print_info "This will install:"
    echo "  • Essential build tools"
    echo "  • Modern CLI tools (fzf, ripgrep, bat, etc.)"
    echo "  • Python development tools"
    echo "  • Neovim (latest)"
    echo "  • Starship prompt"
    echo "  • Selected special tools"
    echo
    
    if confirm "Proceed with quick install?"; then
        update_packages
        
        # Install categories
        install_categories "1,3,4"
        
        # Install Neovim without prompting
        install_neovim_quick
        
        # Install Starship
        install_starship
        
        # Install some special tools
        for tool in zoxide eza tldr lazygit delta; do
            install_special_tool "$tool"
        done
        
    fi
}

# Quick Neovim install (no prompts)
install_neovim_quick() {
    print_header "Installing Neovim (Latest Version)"
    
    # Get latest version
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    
    if [[ -z "$latest_version" ]]; then
        print_error "Could not fetch latest version"
        return 1
    fi
    
    print_info "Installing Neovim $latest_version"
    
    case "$OS" in
        debian)
            # Use tarball method for quick install
            print_step "Installing Neovim via tarball..."
            local temp_dir="$TEMP_DIR/neovim"
            mkdir -p "$temp_dir"
            
            local download_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
            
            if curl -Lo "$temp_dir/nvim-linux-x86_64.tar.gz" "$download_url" && [[ -s "$temp_dir/nvim-linux-x86_64.tar.gz" ]]; then
                cd "$temp_dir"
                tar xzf nvim-linux-x86_64.tar.gz
                
                # Find the extracted directory
                local nvim_dir=$(find . -maxdepth 1 -type d -name "nvim-*" | head -n1)
                
                if [[ -n "$nvim_dir" && -d "$nvim_dir" ]]; then
                    # Remove old installation if exists
                    [[ -d "$HOME/.local/nvim" ]] && rm -rf "$HOME/.local/nvim"
                    
                    # Copy to local directory
                    mkdir -p "$HOME/.local"
                    cp -r "$nvim_dir" "$HOME/.local/nvim"
                    
                    # Create symlink in bin
                    mkdir -p "$HOME/.local/bin"
                    ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
                    
                    cd - &>/dev/null
                    rm -rf "$temp_dir"
                    
                    print_success "Neovim $latest_version installed"
                    INSTALLED_PACKAGES+=("neovim $latest_version (tarball)")
                else
                    print_error "Failed to extract Neovim"
                    return 1
                fi
            else
                print_error "Failed to download Neovim"
                return 1
            fi
            ;;
            
        arch)
            if [[ -n "$AUR_HELPER" ]]; then
                install_aur_package "neovim-git"
            else
                install_package "neovim"
            fi
            ;;
    esac
}

# Main function
main() {
    # Setup
    mkdir -p "$TEMP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    log "Package installer started"
    
    # Detect OS
    detect_os
    
    # Check for AUR helper on Arch
    if [[ "$OS" == "arch" ]]; then
        if command -v yay &>/dev/null; then
            AUR_HELPER="yay"
        elif command -v paru &>/dev/null; then
            AUR_HELPER="paru"
        fi
    fi
    
    while true; do
        show_main_menu
        
        case "$main_choice" in
            1)
                show_category_menu
                if [[ "$choices" != "q" ]]; then
                    update_packages
                    install_categories "$choices"
                    pause_for_user
                fi
                ;;
            2)
                quick_install
                pause_for_user
                ;;
            3)
                if [[ "$OS" == "arch" ]]; then
                    install_aur_helper
                else
                    print_warning "AUR helper is only for Arch-based systems"
                fi
                pause_for_user
                ;;
            4)
                update_packages
                pause_for_user
                ;;
            q|Q)
                break
                ;;
            *)
                print_warning "Invalid choice"
                sleep 2
                ;;
        esac
    done
   
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    # Print summary
    print_summary
    echo
}

# Run the script
main "$@"
