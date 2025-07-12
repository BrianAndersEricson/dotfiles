#!/bin/bash
# GitHub Setup Script - Configure SSH for GitHub
# Version: 2.0.0
# This script helps you set up your device to work with GitHub using SSH

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
readonly LOG_FILE="/tmp/github-setup-$(date +%Y%m%d-%H%M%S).log"
readonly DOTFILES_REPO="BrianAndersEricson/dotfiles"

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

pause_for_user() {
    echo
    read -p "Press Enter to continue... "
    echo
}

confirm() {
    local prompt="${1:-Continue?}"
    read -p "$prompt [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if grep -qi microsoft /proc/version 2>/dev/null; then
            OS="wsl"
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    log "Detected OS: $OS"
}

check_dependencies() {
    local missing=()
    
    # Check for required commands
    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi
    
    if ! command -v ssh-keygen &>/dev/null; then
        missing+=("openssh")
    fi
    
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required tools!"
        print_info "Please install them first:"
        
        if command -v apt &>/dev/null; then
            print_step "sudo apt update && sudo apt install ${missing[*]}"
        elif command -v pacman &>/dev/null; then
            # Fix package names for Arch
            local arch_packages=()
            for pkg in "${missing[@]}"; do
                case "$pkg" in
                    "openssh") arch_packages+=("openssh") ;;
                    *) arch_packages+=("$pkg") ;;
                esac
            done
            print_step "sudo pacman -S ${arch_packages[*]}"
        elif command -v brew &>/dev/null; then
            print_step "brew install ${missing[*]}"
        fi
        
        exit 1
    fi
}

# Step 1: Configure Git
setup_git_config() {
    print_header "Step 1: Git Configuration"
    
    # Check existing config
    local current_name current_email
    current_name=$(git config --global user.name 2>/dev/null || true)
    current_email=$(git config --global user.email 2>/dev/null || true)
    
    if [[ -n "$current_name" && -n "$current_email" ]]; then
        print_info "Current Git configuration:"
        print_info "  Name: $current_name"
        print_info "  Email: $current_email"
        echo
        
        if ! confirm "Do you want to change this configuration?"; then
            return 0
        fi
    fi
    
    # Get user input
    echo "Let's configure your Git identity."
    echo "This will be used for all your commits."
    echo
    
    read -p "Enter your full name: " git_name
    while [[ -z "$git_name" ]]; do
        print_warning "Name cannot be empty"
        read -p "Enter your full name: " git_name
    done
    
    read -p "Enter your email address: " git_email
    while ! [[ "$git_email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
        print_warning "Please enter a valid email address"
        read -p "Enter your email address: " git_email
    done
    
    # Configure Git
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    git config --global init.defaultBranch main
    
    # Additional useful settings
    git config --global pull.rebase false
    git config --global core.editor "${EDITOR:-vim}"
    
    print_success "Git configured successfully!"
    log "Git configured: $git_name <$git_email>"
}

# Step 2: Generate SSH Key
setup_ssh_key() {
    print_header "Step 2: SSH Key Setup"
    
    if [[ -f "$SSH_KEY_PATH" ]]; then
        print_info "You already have an SSH key at: $SSH_KEY_PATH"
        
        if ! confirm "Do you want to create a new SSH key? (This will backup the existing one)"; then
            print_info "Using existing SSH key"
            return 0
        fi
        
        # Backup existing key
        local backup_name="$SSH_KEY_PATH.backup.$(date +%Y%m%d-%H%M%S)"
        mv "$SSH_KEY_PATH" "$backup_name"
        mv "${SSH_KEY_PATH}.pub" "${backup_name}.pub"
        print_info "Existing keys backed up to: $backup_name"
    fi
    
    print_info "Generating a new ED25519 SSH key..."
    print_info "This is more secure than the older RSA keys."
    echo
    
    local email
    email=$(git config --global user.email 2>/dev/null || true)
    
    if [[ -z "$email" ]]; then
        read -p "Enter email for SSH key: " email
    else
        print_info "Using email: $email"
    fi
    
    # Generate SSH key
    ssh-keygen -t ed25519 -C "$email" -f "$SSH_KEY_PATH" -N ""
    
    print_success "SSH key generated successfully!"
    
    # Start SSH agent
    eval "$(ssh-agent -s)" &>/dev/null
    ssh-add "$SSH_KEY_PATH" &>/dev/null
    
    log "SSH key generated for: $email"
}

# Step 3: Add SSH key to GitHub
add_ssh_to_github() {
    print_header "Step 3: Add SSH Key to GitHub"
    
    if [[ ! -f "${SSH_KEY_PATH}.pub" ]]; then
        print_error "No SSH public key found. Please run step 2 first."
        return 1
    fi
    
    print_info "Your SSH public key:"
    echo
    print_colored "$GREEN" "$(cat "${SSH_KEY_PATH}.pub")"
    echo
    
    # Try to copy to clipboard
    local copied=false
    if command -v pbcopy &>/dev/null; then
        cat "${SSH_KEY_PATH}.pub" | pbcopy
        copied=true
    elif command -v xclip &>/dev/null; then
        cat "${SSH_KEY_PATH}.pub" | xclip -selection clipboard
        copied=true
    elif [[ "$OS" == "wsl" ]] && command -v clip.exe &>/dev/null; then
        cat "${SSH_KEY_PATH}.pub" | clip.exe
        copied=true
    fi
    
    if [[ "$copied" == true ]]; then
        print_success "SSH key copied to clipboard!"
    else
        print_info "Please copy the SSH key above"
    fi
    
    echo
    print_step "Now, let's add this key to GitHub:"
    echo
    print_info "1. Open GitHub SSH settings:"
    print_colored "$CYAN" "   https://github.com/settings/keys"
    echo
    print_info "2. Click 'New SSH key' (green button)"
    echo
    print_info "3. Give it a title (e.g., '$(hostname) - $(date +%Y-%m-%d)')"
    echo
    print_info "4. Paste your SSH key into the 'Key' field"
    echo
    print_info "5. Click 'Add SSH key'"
    echo
    
    pause_for_user
}

# Step 4: Switch dotfiles repo to SSH
switch_dotfiles_to_ssh() {
    print_header "Step 4: Switch Dotfiles Repository to SSH"
    
    # Find the dotfiles directory by looking for the git repo
    local dotfiles_dir=""
    local search_dirs=(
        "$HOME/dotfiles"
        "$HOME/.dotfiles"
        "$HOME/Projects/dotfiles"
        "$HOME/projects/dotfiles"
        "$HOME/code/dotfiles"
        "$HOME/Code/dotfiles"
        "$(pwd)"  # Current directory
    )
    
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir/.git" ]]; then
            # Check if this is the dotfiles repo
            if git -C "$dir" remote get-url origin 2>/dev/null | grep -q "$DOTFILES_REPO"; then
                dotfiles_dir="$dir"
                break
            fi
        fi
    done
    
    if [[ -z "$dotfiles_dir" ]]; then
        print_warning "Could not find dotfiles repository automatically."
        print_info "Are you currently in your dotfiles directory?"
        echo
        
        if [[ -d ".git" ]] && git remote get-url origin 2>/dev/null | grep -q "$DOTFILES_REPO"; then
            dotfiles_dir="$(pwd)"
        else
            read -p "Enter the path to your dotfiles directory (or press Enter to skip): " dotfiles_dir
            if [[ -z "$dotfiles_dir" ]]; then
                print_info "Skipping dotfiles repository switch"
                return 0
            fi
        fi
    fi
    
    if [[ ! -d "$dotfiles_dir/.git" ]]; then
        print_error "Not a git repository: $dotfiles_dir"
        return 1
    fi
    
    # Get current remote URL
    local current_url
    current_url=$(git -C "$dotfiles_dir" remote get-url origin 2>/dev/null || true)
    
    if [[ -z "$current_url" ]]; then
        print_error "No origin remote found in $dotfiles_dir"
        return 1
    fi
    
    print_info "Found dotfiles repository at: $dotfiles_dir"
    print_info "Current remote URL: $current_url"
    
    # Check if already using SSH
    if [[ "$current_url" == git@github.com:* ]]; then
        print_success "Already using SSH for dotfiles repository!"
        return 0
    fi
    
    # Switch to SSH
    local new_url="git@github.com:$DOTFILES_REPO.git"
    print_info "Switching to SSH URL: $new_url"
    
    if git -C "$dotfiles_dir" remote set-url origin "$new_url"; then
        print_success "Successfully switched dotfiles repository to SSH!"
        log "Switched dotfiles repo to SSH: $dotfiles_dir"
    else
        print_error "Failed to switch remote URL"
        return 1
    fi
}

# Step 5: Test SSH connection
test_ssh_connection() {
    print_header "Step 5: Test SSH Connection"
    
    print_info "Testing SSH connection to GitHub..."
    echo
    
    # Ensure SSH agent is running and key is added
    eval "$(ssh-agent -s)" &>/dev/null
    ssh-add "$SSH_KEY_PATH" &>/dev/null
    
    # Test connection
    local ssh_output
    ssh_output=$(ssh -T git@github.com 2>&1 || true)
    
    if echo "$ssh_output" | grep -q "successfully authenticated"; then
        print_success "SSH connection successful! ✨"
        print_info "You're all set to use Git with SSH!"
        
        # Extract username from SSH output
        local github_user
        github_user=$(echo "$ssh_output" | grep -o "Hi [^!]*" | cut -d' ' -f2)
        if [[ -n "$github_user" ]]; then
            print_info "Authenticated as: $github_user"
        fi
    else
        print_error "SSH connection test failed!"
        print_info "Output: $ssh_output"
        echo
        print_info "Please make sure you've added your SSH key to GitHub."
        print_info "You can manually test with: ssh -T git@github.com"
        return 1
    fi
    
    # If we found a dotfiles directory, test pushing/pulling
    local dotfiles_dir=""
    for dir in "$HOME/dotfiles" "$HOME/.dotfiles" "$(pwd)"; do
        if [[ -d "$dir/.git" ]] && git -C "$dir" remote get-url origin 2>/dev/null | grep -q "$DOTFILES_REPO"; then
            dotfiles_dir="$dir"
            break
        fi
    done
    
    if [[ -n "$dotfiles_dir" ]]; then
        echo
        print_info "Testing Git operations on dotfiles repository..."
        
        # Test fetch
        if git -C "$dotfiles_dir" fetch --dry-run 2>/dev/null; then
            print_success "Git fetch test successful!"
        else
            print_warning "Git fetch test failed - you may need to check your permissions"
        fi
    fi
}

# Create helpful aliases
setup_github_aliases() {
    print_header "Helpful Git Aliases (Optional)"
    
    print_info "Would you like to set up some helpful Git aliases?"
    echo
    
    if ! confirm "Set up Git aliases?"; then
        return 0
    fi
    
    # Define aliases
    git config --global alias.st "status -sb"
    git config --global alias.co "checkout"
    git config --global alias.br "branch"
    git config --global alias.ci "commit"
    git config --global alias.last "log -1 HEAD"
    git config --global alias.unstage "reset HEAD --"
    git config --global alias.visual "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    
    print_success "Git aliases configured!"
    echo
    print_info "You can now use:"
    print_step "git st     # Short status"
    print_step "git co     # Checkout"
    print_step "git br     # Branch"
    print_step "git ci     # Commit"
    print_step "git last   # Show last commit"
    print_step "git visual # Pretty log view"
}

# Show current configuration
show_current_config() {
    print_header "Current Configuration"
    
    # Git config
    print_info "Git Configuration:"
    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "Not set")
    git_email=$(git config --global user.email 2>/dev/null || echo "Not set")
    echo "  Name: $git_name"
    echo "  Email: $git_email"
    echo
    
    # SSH key
    print_info "SSH Key:"
    if [[ -f "$SSH_KEY_PATH" ]]; then
        echo "  Key exists: $SSH_KEY_PATH"
        echo "  Fingerprint: $(ssh-keygen -lf "$SSH_KEY_PATH" | awk '{print $2}')"
    else
        echo "  No SSH key found"
    fi
    echo
    
    # Test SSH connection
    print_step "Testing SSH connection to GitHub..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        print_success "SSH connection to GitHub: Working ✓"
    else
        print_warning "SSH connection to GitHub: Not working"
    fi
    
    # Check dotfiles repo
    echo
    print_info "Dotfiles Repository:"
    local dotfiles_dir=""
    for dir in "$HOME/dotfiles" "$HOME/.dotfiles" "$(pwd)"; do
        if [[ -d "$dir/.git" ]] && git -C "$dir" remote get-url origin 2>/dev/null | grep -q "$DOTFILES_REPO"; then
            dotfiles_dir="$dir"
            break
        fi
    done
    
    if [[ -n "$dotfiles_dir" ]]; then
        local remote_url
        remote_url=$(git -C "$dotfiles_dir" remote get-url origin)
        echo "  Location: $dotfiles_dir"
        echo "  Remote URL: $remote_url"
        if [[ "$remote_url" == git@github.com:* ]]; then
            print_success "  Using SSH: Yes ✓"
        else
            print_warning "  Using SSH: No (HTTPS)"
        fi
    else
        echo "  Not found in standard locations"
    fi
    
    pause_for_user
}

# Main menu
show_menu() {
    echo
    print_colored "$CYAN" "═══════════════════════════════════════════════════════════════"
    print_colored "$CYAN" "                   🐙 GitHub SSH Setup Assistant                "
    print_colored "$CYAN" "═══════════════════════════════════════════════════════════════"
    echo
    
    print_info "What would you like to do?"
    echo
    echo "  1) 🚀 Complete setup (recommended for new devices)"
    echo "  2) 🔧 Configure Git name and email only"
    echo "  3) 🔑 Generate SSH key only"
    echo "  4) 🔄 Switch dotfiles repo to SSH"
    echo "  5) 🧪 Test SSH connection"
    echo "  6) 📋 Show current configuration"
    echo "  7) 🎨 Set up Git aliases"
    echo "  8) 🧹 Clear screen"
    echo "  q) 🚪 Quit"
    echo
    read -p "Enter your choice: " -n 1 choice
    echo
}

# Main function
main() {
    # Initialize
    mkdir -p "$(dirname "$LOG_FILE")"
    log "GitHub setup started"
    
    # Detect OS and check dependencies
    detect_os
    check_dependencies
    
    # Show welcome banner once at start
    clear
    print_colored "$CYAN" "╔════════════════════════════════════════════════════════════════╗"
    print_colored "$CYAN" "║               🐙 GitHub SSH Setup Assistant                    ║"
    print_colored "$CYAN" "║                                                                ║"
    print_colored "$CYAN" "║  This script will help you set up your device to work         ║"
    print_colored "$CYAN" "║  seamlessly with GitHub using SSH keys.                       ║"
    print_colored "$CYAN" "╚════════════════════════════════════════════════════════════════╝"
    
    pause_for_user
    
    while true; do
        show_menu
        
        case "$choice" in
            1)
                setup_git_config
                setup_ssh_key
                add_ssh_to_github
                switch_dotfiles_to_ssh
                test_ssh_connection
                echo
                if confirm "Would you like to set up Git aliases?"; then
                    setup_github_aliases
                fi
                echo
                print_success "Complete setup finished! 🎉"
                print_info "You can now push/pull your dotfiles using SSH!"
                pause_for_user
                ;;
            2)
                setup_git_config
                pause_for_user
                ;;
            3)
                setup_ssh_key
                add_ssh_to_github
                pause_for_user
                ;;
            4)
                switch_dotfiles_to_ssh
                pause_for_user
                ;;
            5)
                test_ssh_connection
                pause_for_user
                ;;
            6)
                show_current_config
                ;;
            7)
                setup_github_aliases
                pause_for_user
                ;;
            8)
                clear
                ;;
            q|Q)
                print_info "Thanks for using GitHub SSH Setup Assistant!"
                break
                ;;
            *)
                print_warning "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
    
    echo
    print_success "All done! 🎉"
    print_info "Log file: $LOG_FILE"
    echo
    print_info "Happy coding! 🚀"
}

# Run the script
main
