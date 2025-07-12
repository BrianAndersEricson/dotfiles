#!/bin/bash
# GitHub Setup Script - Configure SSH and GPG for GitHub
# Version: 1.0.0
# This script helps you set up your device to work with GitHub

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
    
    if ! command -v gpg &>/dev/null; then
        missing+=("gnupg")
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
                    "gnupg") arch_packages+=("gnupg") ;;
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
    
    # Test SSH connection
    print_info "Testing SSH connection to GitHub..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        print_success "SSH connection successful! You're connected to GitHub."
    else
        print_warning "SSH connection test failed, but this might be normal."
        print_info "The connection might still work. Let's continue..."
    fi
}

# Step 4: Setup GPG (optional)
setup_gpg_key() {
    print_header "Step 4: GPG Key Setup (Optional)"
    
    print_info "GPG signing adds an extra layer of verification to your commits."
    print_info "It shows a 'Verified' badge on GitHub."
    echo
    
    if ! confirm "Do you want to set up GPG signing?"; then
        print_info "Skipping GPG setup"
        return 0
    fi
    
    local name email
    name=$(git config --global user.name)
    email=$(git config --global user.email)
    
    # Check for existing key
    local existing_keyid=""
    if gpg --list-secret-keys --keyid-format=long "$email" &>/dev/null; then
        existing_keyid=$(gpg --list-secret-keys --keyid-format=long "$email" | 
                        grep -E '^sec' | head -n1 | awk '{print $2}' | cut -d'/' -f2)
        
        print_info "You already have a GPG key for $email"
        print_info "Key ID: $existing_keyid"
        echo
        print_info "Options:"
        echo "  1) Use existing key"
        echo "  2) Create a new key"
        echo "  3) Remove existing key and create new one"
        echo
        read -p "Choose an option (1-3): " -n 1 gpg_choice
        echo
        
        case "$gpg_choice" in
            1)
                # Use existing key
                git config --global user.signingkey "$existing_keyid"
                git config --global commit.gpgsign true
                configure_gpg_agent
                print_success "Configured Git to use existing GPG key"
                return 0
                ;;
            2)
                # Create additional key (continue with normal flow)
                ;;
            3)
                # Remove existing key
                print_warning "Removing existing GPG key..."
                gpg --delete-secret-keys "$existing_keyid" 2>/dev/null || true
                gpg --delete-keys "$email" 2>/dev/null || true
                print_info "Existing key removed"
                ;;
            *)
                print_error "Invalid choice"
                return 1
                ;;
        esac
    fi
    
    print_info "Generating GPG key..."
    print_info "This might take a moment..."
    echo
    
    # Create GPG directory with proper permissions
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg
    
    # Configure GPG for no passphrase
    configure_gpg_agent
    
    # Create batch file for GPG key generation
    local batch_file="/tmp/gpg-batch-$"
    cat > "$batch_file" <<EOF
%echo Generating GPG key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $name
Name-Email: $email
Expire-Date: 2y
%no-protection
%commit
%echo done
EOF
    
    # Generate key
    if gpg --batch --generate-key "$batch_file"; then
        rm -f "$batch_file"
        print_success "GPG key generated!"
    else
        rm -f "$batch_file"
        print_error "Failed to generate GPG key"
        return 1
    fi
    
    # Get key ID
    local keyid
    keyid=$(gpg --list-secret-keys --keyid-format=long "$email" | 
           grep -E '^sec' | head -n1 | awk '{print $2}' | cut -d'/' -f2)
    
    if [[ -z "$keyid" ]]; then
        print_error "Failed to find generated GPG key"
        return 1
    fi
    
    # Configure Git to use GPG
    git config --global user.signingkey "$keyid"
    git config --global commit.gpgsign true
    
    print_success "GPG key generated and configured!"
    print_info "Key ID: $keyid"
    log "GPG key generated: $keyid"
}

# Configure GPG agent for no passphrase
configure_gpg_agent() {
    # Create GPG config files
    cat > ~/.gnupg/gpg.conf <<EOF
use-agent
pinentry-mode loopback
no-tty
EOF
    
    cat > ~/.gnupg/gpg-agent.conf <<EOF
allow-loopback-pinentry
default-cache-ttl 31536000
max-cache-ttl 31536000
EOF
    
    # Set proper permissions
    chmod 600 ~/.gnupg/gpg.conf
    chmod 600 ~/.gnupg/gpg-agent.conf
    
    # Restart GPG agent
    gpgconf --kill gpg-agent 2>/dev/null || true
    gpgconf --launch gpg-agent
    
    # For WSL, we might need additional config
    if [[ "$OS" == "wsl" ]]; then
        export GPG_TTY=$(tty)
    fi
}

# Step 5: Add GPG key to GitHub
add_gpg_to_github() {
    print_header "Step 5: Add GPG Key to GitHub"
    
    local email keyid
    email=$(git config --global user.email)
    keyid=$(git config --global user.signingkey 2>/dev/null || true)
    
    if [[ -z "$keyid" ]]; then
        print_info "No GPG key configured. Skipping..."
        return 0
    fi
    
    print_info "Your GPG public key:"
    echo
    
    # Export public key
    local gpg_public
    gpg_public=$(gpg --armor --export "$keyid")
    print_colored "$GREEN" "$gpg_public"
    echo
    
    # Try to copy to clipboard
    local copied=false
    if command -v pbcopy &>/dev/null; then
        echo "$gpg_public" | pbcopy
        copied=true
    elif command -v xclip &>/dev/null; then
        echo "$gpg_public" | xclip -selection clipboard
        copied=true
    elif [[ "$OS" == "wsl" ]] && command -v clip.exe &>/dev/null; then
        echo "$gpg_public" | clip.exe
        copied=true
    fi
    
    if [[ "$copied" == true ]]; then
        print_success "GPG key copied to clipboard!"
    else
        print_info "Please copy the GPG key above"
    fi
    
    echo
    print_step "Now, let's add this key to GitHub:"
    echo
    print_info "1. Open GitHub GPG settings:"
    print_colored "$CYAN" "   https://github.com/settings/keys"
    echo
    print_info "2. Click 'New GPG key' (green button)"
    echo
    print_info "3. Paste your GPG key"
    echo
    print_info "4. Click 'Add GPG key'"
    echo
    
    pause_for_user
}

# Step 6: Test everything
test_github_setup() {
    print_header "Step 6: Test Your Setup"
    
    print_info "Let's create a test repository to verify everything works!"
    echo
    
    if ! confirm "Create a test repository?"; then
        return 0
    fi
    
    # Create test repo
    local test_dir="$HOME/github-test-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    print_step "Creating test repository..."
    git init
    echo "# GitHub Test Repository" > README.md
    echo "This is a test repository created on $(date)" >> README.md
    
    git add README.md
    
    # Check if GPG signing is enabled
    if [[ "$(git config --global commit.gpgsign)" == "true" ]]; then
        print_info "Creating GPG-signed commit..."
        
        # Make sure GPG agent is configured
        configure_gpg_agent
        
        # Set GPG_TTY for terminal
        export GPG_TTY=$(tty)
        
        # Try to commit with explicit no-gpg-sign first to test
        if ! git commit -m "Initial commit - testing GitHub setup" 2>/dev/null; then
            print_warning "GPG signing failed. Trying without signing..."
            git commit --no-gpg-sign -m "Initial commit - testing GitHub setup"
            print_warning "Commit created without GPG signature."
            print_info "You may need to troubleshoot GPG signing separately."
        else
            print_success "GPG-signed commit created successfully!"
            # Show signature
            git log --show-signature -1
        fi
    else
        git commit -m "Initial commit - testing GitHub setup"
        print_success "Commit created successfully!"
    fi
    
    print_success "Test repository created at: $test_dir"
    echo
    print_info "To push this to GitHub:"
    print_step "1. Create a new repository on GitHub: https://github.com/new"
    print_step "2. Don't initialize it with any files"
    print_step "3. Run these commands:"
    echo
    print_colored "$YELLOW" "cd $test_dir"
    print_colored "$YELLOW" "git remote add origin git@github.com:YOUR_USERNAME/REPO_NAME.git"
    print_colored "$YELLOW" "git push -u origin main"
    echo
    
    print_info "You can delete this test repo later with:"
    print_colored "$YELLOW" "rm -rf $test_dir"
}

# Step 7: Create helpful aliases
setup_github_aliases() {
    print_header "Step 7: Helpful Git Aliases (Optional)"
    
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

# Main menu
show_menu() {
    # Don't clear - let user see previous output
    echo
    print_colored "$CYAN" "═══════════════════════════════════════════════════════════════"
    print_colored "$CYAN" "                   🐙 GitHub Setup Assistant                   "
    print_colored "$CYAN" "═══════════════════════════════════════════════════════════════"
    echo
    
    print_info "What would you like to do?"
    echo
    echo "  1) 🚀 Complete setup (recommended for new devices)"
    echo "  2) 🔧 Configure Git name and email only"
    echo "  3) 🔑 Generate SSH key only"
    echo "  4) 📝 Set up GPG signing only"
    echo "  5) 🧪 Test current setup"
    echo "  6) 📋 Show current configuration"
    echo "  7) 🧹 Clear screen"
    echo "  q) 🚪 Quit"
    echo
    read -p "Enter your choice: " -n 1 choice
    echo
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
        
        # Test SSH connection
        print_step "Testing SSH connection to GitHub..."
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            print_success "SSH connection to GitHub: Working ✓"
        else
            print_warning "SSH connection to GitHub: Not working"
        fi
    else
        echo "  No SSH key found"
    fi
    echo
    
    # GPG key
    print_info "GPG Key:"
    local gpg_key
    gpg_key=$(git config --global user.signingkey 2>/dev/null || echo "Not configured")
    if [[ "$gpg_key" != "Not configured" ]]; then
        echo "  Key ID: $gpg_key"
        echo "  Signing enabled: $(git config --global commit.gpgsign || echo "false")"
        
        # Check if key exists
        if gpg --list-secret-keys "$gpg_key" &>/dev/null; then
            print_success "GPG key status: Valid ✓"
        else
            print_warning "GPG key status: Key not found!"
        fi
    else
        echo "  No GPG signing configured"
    fi
    
    pause_for_user
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
    print_colored "$CYAN" "║               🐙 GitHub Setup Assistant                        ║"
    print_colored "$CYAN" "║                                                                ║"
    print_colored "$CYAN" "║  This script will help you set up your device to work         ║"
    print_colored "$CYAN" "║  seamlessly with GitHub using SSH keys and GPG signing.       ║"
    print_colored "$CYAN" "╚════════════════════════════════════════════════════════════════╝"
    
    pause_for_user
    
    while true; do
        show_menu
        
        case "$choice" in
            1)
                setup_git_config
                setup_ssh_key
                add_ssh_to_github
                setup_gpg_key
                add_gpg_to_github
                test_github_setup
                setup_github_aliases
                echo
                print_success "Complete setup finished!"
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
                setup_gpg_key
                add_gpg_to_github
                pause_for_user
                ;;
            5)
                test_github_setup
                pause_for_user
                ;;
            6)
                show_current_config
                ;;
            7)
                clear
                ;;
            q|Q)
                print_info "Thanks for using GitHub Setup Assistant!"
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
