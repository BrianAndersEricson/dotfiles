#!/bin/bash
# Dotfiles Linker Script
# Version: 1.0.0
# Manages dotfiles repository and creates symlinks

set -euo pipefail

# Configuration
readonly DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.src/dotfiles}"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
readonly LOG_FILE="/tmp/dotfiles-linker-$(date +%Y%m%d-%H%M%S).log"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Global variables
DRY_RUN=false
FORCE=false
VERBOSE=false

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

log_verbose() {
    [[ "$VERBOSE" == true ]] && log "$@"
}

confirm() {
    local prompt="${1:-Continue?}"
    [[ "$FORCE" == true ]] && return 0
    read -p "$prompt [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

pause_for_user() {
    [[ "$FORCE" == true ]] && return
    echo
    read -p "Press Enter to continue... "
    echo
}

# Configuration file mappings
declare -A CONFIG_MAPPINGS=(
    # Shell configurations
    ["$DOTFILES_DIR/.bashrc"]="$HOME/.bashrc"
    ["$DOTFILES_DIR/.bash_profile"]="$HOME/.bash_profile"
    ["$DOTFILES_DIR/.bash_aliases"]="$HOME/.bash_aliases"
    ["$DOTFILES_DIR/.bash_logout"]="$HOME/.bash_logout"
    ["$DOTFILES_DIR/.profile"]="$HOME/.profile"
    ["$DOTFILES_DIR/.zshrc"]="$HOME/.zshrc"
    ["$DOTFILES_DIR/.zprofile"]="$HOME/.zprofile"
    ["$DOTFILES_DIR/.zshenv"]="$HOME/.zshenv"
    
    # Editor configurations
    ["$DOTFILES_DIR/.vimrc"]="$HOME/.vimrc"
    ["$DOTFILES_DIR/.vim"]="$HOME/.vim"
    ["$DOTFILES_DIR/.config/nvim"]="$CONFIG_DIR/nvim"
    
    # Terminal configurations
    ["$DOTFILES_DIR/.tmux.conf"]="$HOME/.tmux.conf"
    ["$DOTFILES_DIR/.config/tmux"]="$CONFIG_DIR/tmux"
    ["$DOTFILES_DIR/.config/alacritty"]="$CONFIG_DIR/alacritty"
    ["$DOTFILES_DIR/.config/kitty"]="$CONFIG_DIR/kitty"
    ["$DOTFILES_DIR/.config/wezterm"]="$CONFIG_DIR/wezterm"
    ["$DOTFILES_DIR/.config/terminator"]="$CONFIG_DIR/terminator"
    
    # Development tools
    ["$DOTFILES_DIR/.gitconfig"]="$HOME/.gitconfig"
    ["$DOTFILES_DIR/.gitignore_global"]="$HOME/.gitignore_global"
    ["$DOTFILES_DIR/.config/git"]="$CONFIG_DIR/git"
    ["$DOTFILES_DIR/.config/gh"]="$CONFIG_DIR/gh"
    ["$DOTFILES_DIR/.config/lazygit"]="$CONFIG_DIR/lazygit"
    
    # Shell tools
    ["$DOTFILES_DIR/.config/starship.toml"]="$CONFIG_DIR/starship.toml"
    ["$DOTFILES_DIR/.config/fish"]="$CONFIG_DIR/fish"
    ["$DOTFILES_DIR/.config/zoxide"]="$CONFIG_DIR/zoxide"
    
    # Other configurations
    ["$DOTFILES_DIR/.config/htop"]="$CONFIG_DIR/htop"
    ["$DOTFILES_DIR/.config/bat"]="$CONFIG_DIR/bat"
    ["$DOTFILES_DIR/.config/bottom"]="$CONFIG_DIR/bottom"
    ["$DOTFILES_DIR/.config/ripgrep"]="$CONFIG_DIR/ripgrep"
    ["$DOTFILES_DIR/.rgrc"]="$HOME/.rgrc"
    ["$DOTFILES_DIR/.fdignore"]="$HOME/.fdignore"
    
    # Desktop environment (optional)
    ["$DOTFILES_DIR/.config/i3"]="$CONFIG_DIR/i3"
    ["$DOTFILES_DIR/.config/sway"]="$CONFIG_DIR/sway"
    ["$DOTFILES_DIR/.config/polybar"]="$CONFIG_DIR/polybar"
    ["$DOTFILES_DIR/.config/rofi"]="$CONFIG_DIR/rofi"
    ["$DOTFILES_DIR/.config/dunst"]="$CONFIG_DIR/dunst"
    
    # Language specific
    ["$DOTFILES_DIR/.config/pip"]="$CONFIG_DIR/pip"
    ["$DOTFILES_DIR/.npmrc"]="$HOME/.npmrc"
    ["$DOTFILES_DIR/.cargo/config.toml"]="$HOME/.cargo/config.toml"
    ["$DOTFILES_DIR/.config/go"]="$CONFIG_DIR/go"
)

# Initialize dotfiles repository
init_repository() {
    print_header "Initialize Dotfiles Repository"
    
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        print_info "Repository already exists at $DOTFILES_DIR"
        
        if confirm "Pull latest changes?"; then
            cd "$DOTFILES_DIR"
            if git pull origin main 2>/dev/null; then
                print_success "Repository updated"
            else
                print_warning "Could not pull changes (this is normal for new repos)"
            fi
            cd - >/dev/null
        fi
        return 0
    fi
    
    print_step "Creating new repository at $DOTFILES_DIR"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would create repository at $DOTFILES_DIR"
        return 0
    fi
    
    mkdir -p "$DOTFILES_DIR"
    cd "$DOTFILES_DIR"
    
    # Initialize git
    git init
    git branch -M main
    
    # Create directory structure
    mkdir -p .config/{git,nvim,tmux,alacritty,starship,fish,bat,htop}
    mkdir -p scripts docs .cargo
    
    # Create README
    create_readme
    
    # Create .gitignore
    create_gitignore
    
    git add .
    git commit -m "Initial dotfiles repository structure"
    
    print_success "Repository initialized"
    cd - >/dev/null
}

# Create README
create_readme() {
    cat > "$DOTFILES_DIR/README.md" << 'EOF'
# Dotfiles

My personal configuration files managed by the dotfiles linker script.

## Structure

```
.
├── .bashrc              # Bash configuration
├── .bash_aliases        # Shell aliases
├── .gitconfig           # Git configuration
├── .tmux.conf           # Tmux configuration
├── .vimrc               # Vim configuration
└── .config/             # Application configurations
    ├── nvim/            # Neovim
    ├── alacritty/       # Alacritty terminal
    ├── starship.toml    # Starship prompt
    └── ...
```

## Installation

```bash
# Clone this repository
git clone https://github.com/USERNAME/dotfiles.git ~/.src/dotfiles

# Run the linker script
./dotfiles-linker.sh --link
```

## Management

- `./dotfiles-linker.sh --discover` - Find and import existing configs
- `./dotfiles-linker.sh --link` - Create symlinks
- `./dotfiles-linker.sh --check` - Check link status
- `./dotfiles-linker.sh --unlink` - Remove symlinks
EOF
}

# Create .gitignore
create_gitignore() {
    cat > "$DOTFILES_DIR/.gitignore" << 'EOF'
# Temporary files
*.tmp
*.swp
*.swo
*~
.DS_Store

# Sensitive data
.env
.secrets
*.key
*.pem

# Cache and logs
.cache/
*.log
.netrwhist

# Language specific
__pycache__/
*.pyc
node_modules/
.cargo/registry/
.cargo/git/

# Editor
.vscode/
.idea/

# Local overrides
*.local
EOF
}

# Discover existing configurations
discover_configs() {
    print_header "Discovering Existing Configurations"
    
    local found_configs=()
    local total_size=0
    
    print_step "Scanning for configuration files..."
    
    # Check each potential source location
    for source in "${!CONFIG_MAPPINGS[@]}"; do
        local target="${CONFIG_MAPPINGS[$source]}"
        local relative_source="${source#$DOTFILES_DIR/}"
        
        # Skip if source already exists in dotfiles
        [[ -e "$source" ]] && continue
        
        # Check if target exists and is not a symlink
        if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
            if [[ -f "$target" ]]; then
                local size=$(stat -f%z "$target" 2>/dev/null || stat -c%s "$target" 2>/dev/null || echo "0")
                total_size=$((total_size + size))
                found_configs+=("$target|$source|file|$size")
            elif [[ -d "$target" ]]; then
                local count=$(find "$target" -type f 2>/dev/null | wc -l)
                found_configs+=("$target|$source|dir|$count")
            fi
        fi
    done
    
    if [[ ${#found_configs[@]} -eq 0 ]]; then
        print_info "No existing configurations found to import"
        return 0
    fi
    
    print_info "Found ${#found_configs[@]} configuration(s):"
    echo
    
    local i=1
    for config in "${found_configs[@]}"; do
        IFS='|' read -r target source type meta <<< "$config"
        if [[ "$type" == "file" ]]; then
            printf "  %2d) %-40s (%s bytes)\n" "$i" "${target#$HOME/}" "$meta"
        else
            printf "  %2d) %-40s (%s files)\n" "$i" "${target#$HOME/}/" "$meta"
        fi
        ((i++))
    done
    
    echo
    read -p "Select configs to import (e.g., 1,3,5 or 'all', 'none'): " choices
    
    if [[ "$choices" == "none" ]]; then
        return 0
    fi
    
    local selected=()
    if [[ "$choices" == "all" ]]; then
        selected=("${found_configs[@]}")
    else
        IFS=',' read -ra choice_array <<< "$choices"
        for choice in "${choice_array[@]}"; do
            choice=$(echo "$choice" | tr -d ' ')
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -le ${#found_configs[@]} ]]; then
                selected+=("${found_configs[$((choice-1))]}")
            fi
        done
    fi
    
    if [[ ${#selected[@]} -eq 0 ]]; then
        print_warning "No configurations selected"
        return 0
    fi
    
    import_configs "${selected[@]}"
}

# Import configurations
import_configs() {
    local configs=("$@")
    
    print_step "Importing ${#configs[@]} configuration(s)..."
    
    for config in "${configs[@]}"; do
        IFS='|' read -r target source type meta <<< "$config"
        
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would import: ${target#$HOME/} → ${source#$DOTFILES_DIR/}"
            continue
        fi
        
        # Create parent directory
        local parent_dir=$(dirname "$source")
        mkdir -p "$parent_dir"
        
        # Copy configuration
        if [[ "$type" == "file" ]]; then
            cp "$target" "$source"
            print_success "Imported: ${target#$HOME/}"
        else
            cp -r "$target" "$source"
            print_success "Imported: ${target#$HOME/}/"
        fi
        
        log "Imported: $target → $source"
    done
    
    # Add to git
    if [[ "$DRY_RUN" == false ]] && [[ -d "$DOTFILES_DIR/.git" ]]; then
        cd "$DOTFILES_DIR"
        git add .
        git commit -m "Import existing configurations" 2>/dev/null || true
        cd - >/dev/null
    fi
}

# Create symlinks
create_links() {
    print_header "Creating Symlinks"
    
    local created=0
    local skipped=0
    local failed=0
    
    # Ensure config directory exists
    mkdir -p "$CONFIG_DIR"
    
    for source in "${!CONFIG_MAPPINGS[@]}"; do
        local target="${CONFIG_MAPPINGS[$source]}"
        
        # Skip if source doesn't exist
        if [[ ! -e "$source" ]]; then
            log_verbose "Skipping non-existent source: $source"
            ((skipped++))
            continue
        fi
        
        # Check if target already exists
        if [[ -L "$target" ]]; then
            local current_source=$(readlink "$target")
            if [[ "$current_source" == "$source" ]]; then
                log_verbose "Already linked: ${target#$HOME/}"
                ((skipped++))
                continue
            else
                print_warning "Different symlink exists: ${target#$HOME/} → $current_source"
                if ! confirm "Replace with link to $source?"; then
                    ((skipped++))
                    continue
                fi
                rm "$target"
            fi
        elif [[ -e "$target" ]]; then
            # Backup existing file/directory
            backup_file "$target"
        fi
        
        # Create symlink
        if create_symlink "$source" "$target"; then
            ((created++))
        else
            ((failed++))
        fi
    done
    
    print_info "Summary: $created created, $skipped skipped, $failed failed"
}

# Create a single symlink
create_symlink() {
    local source="$1"
    local target="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would link: ${target#$HOME/} → ${source#$DOTFILES_DIR/}"
        return 0
    fi
    
    # Ensure parent directory exists
    local parent_dir=$(dirname "$target")
    mkdir -p "$parent_dir"
    
    # Create symlink
    if ln -sf "$source" "$target" 2>/dev/null; then
        print_success "Linked: ${target#$HOME/} → ${source#$DOTFILES_DIR/}"
        log "Created symlink: $target → $source"
        return 0
    else
        print_error "Failed to link: ${target#$HOME/}"
        log "Failed to create symlink: $target → $source"
        return 1
    fi
}

# Backup existing file
backup_file() {
    local file="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would backup: ${file#$HOME/}"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    local backup_name="$BACKUP_DIR/$(basename "$file")"
    
    # Handle multiple backups of same file
    if [[ -e "$backup_name" ]]; then
        local i=1
        while [[ -e "${backup_name}.${i}" ]]; do
            ((i++))
        done
        backup_name="${backup_name}.${i}"
    fi
    
    mv "$file" "$backup_name"
    print_info "Backed up: ${file#$HOME/} → ${backup_name#$BACKUP_DIR/}"
    log "Backed up: $file → $backup_name"
}

# Check symlink status
check_links() {
    print_header "Checking Symlink Status"
    
    local valid=0
    local broken=0
    local missing=0
    local different=0
    
    for source in "${!CONFIG_MAPPINGS[@]}"; do
        local target="${CONFIG_MAPPINGS[$source]}"
        local status=""
        
        if [[ ! -e "$source" ]]; then
            # Source doesn't exist
            continue
        fi
        
        if [[ -L "$target" ]]; then
            local link_target=$(readlink "$target")
            if [[ "$link_target" == "$source" ]]; then
                ((valid++))
                [[ "$VERBOSE" == true ]] && print_success "✓ ${target#$HOME/}"
            elif [[ ! -e "$link_target" ]]; then
                ((broken++))
                print_error "✗ ${target#$HOME/} (broken link)"
            else
                ((different++))
                print_warning "⚠ ${target#$HOME/} → $link_target (different)"
            fi
        elif [[ -e "$target" ]]; then
            ((different++))
            print_warning "⚠ ${target#$HOME/} (not a symlink)"
        else
            ((missing++))
            print_info "○ ${target#$HOME/} (not linked)"
        fi
    done
    
    echo
    print_info "Summary:"
    print_success "  Valid links: $valid"
    [[ $missing -gt 0 ]] && print_info "  Missing links: $missing"
    [[ $broken -gt 0 ]] && print_error "  Broken links: $broken"
    [[ $different -gt 0 ]] && print_warning "  Different files: $different"
}

# Remove symlinks
unlink_all() {
    print_header "Removing Symlinks"
    
    if ! confirm "Remove all dotfile symlinks?"; then
        return 0
    fi
    
    local removed=0
    
    for source in "${!CONFIG_MAPPINGS[@]}"; do
        local target="${CONFIG_MAPPINGS[$source]}"
        
        if [[ -L "$target" ]]; then
            local link_target=$(readlink "$target")
            if [[ "$link_target" == "$source" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] Would remove: ${target#$HOME/}"
                else
                    rm "$target"
                    print_success "Removed: ${target#$HOME/}"
                    ((removed++))
                fi
            fi
        fi
    done
    
    print_info "Removed $removed symlink(s)"
}

# Show help
show_help() {
    cat << EOF
Dotfiles Linker - Configuration Management Script

Usage: $(basename "$0") [OPTIONS] [COMMAND]

Commands:
  init        Initialize dotfiles repository
  discover    Find and import existing configurations
  link        Create symlinks (default)
  check       Check current symlink status
  unlink      Remove all symlinks
  
Options:
  -d, --dry-run     Show what would be done without making changes
  -f, --force       Skip confirmations
  -v, --verbose     Show detailed output
  -h, --help        Show this help message
  
Environment:
  DOTFILES_DIR      Location of dotfiles repository (default: ~/.src/dotfiles)
  
Examples:
  $(basename "$0") --dry-run discover    # Preview configuration discovery
  $(basename "$0") link                  # Create all symlinks
  $(basename "$0") --verbose check       # Detailed status check
EOF
}

# Main menu
show_menu() {
    print_colored "$CYAN" "╔════════════════════════════════════════════════════════════════╗"
    print_colored "$CYAN" "║              🔗 Dotfiles Linker v1.0.0                         ║"
    print_colored "$CYAN" "╚════════════════════════════════════════════════════════════════╝"
    echo
    
    print_info "Dotfiles location: $DOTFILES_DIR"
    [[ "$DRY_RUN" == true ]] && print_warning "DRY RUN MODE - No changes will be made"
    echo
    
    echo "What would you like to do?"
    echo
    echo "  1) 🏗️  Initialize dotfiles repository"
    echo "  2) 🔍 Discover and import existing configs"
    echo "  3) 🔗 Create symlinks"
    echo "  4) 📊 Check symlink status"
    echo "  5) 🗑️  Remove symlinks"
    echo "  6) 🚀 Complete setup (init + discover + link)"
    echo "  q) 🚪 Quit"
    echo
    read -p "Enter your choice: " -n 1 choice
    echo
}

# Main function
main() {
    local command=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dry-run)
                DRY_RUN=true
                ;;
            -f|--force)
                FORCE=true
                ;;
            -v|--verbose)
                VERBOSE=true
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            init|discover|link|check|unlink)
                command="$1"
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    
    # Setup
    mkdir -p "$(dirname "$LOG_FILE")"
    log "Dotfiles linker started"
    [[ "$DRY_RUN" == true ]] && log "DRY RUN MODE"
    
    # Execute command if provided
    if [[ -n "$command" ]]; then
        case "$command" in
            init) init_repository ;;
            discover) 
                init_repository
                discover_configs 
                ;;
            link) create_links ;;
            check) check_links ;;
            unlink) unlink_all ;;
        esac
        
        echo
        print_info "Log file: $LOG_FILE"
        exit 0
    fi
    
    # Interactive menu
    while true; do
        show_menu
        
        case "$choice" in
            1)
                init_repository
                pause_for_user
                ;;
            2)
                init_repository
                discover_configs
                pause_for_user
                ;;
            3)
                create_links
                pause_for_user
                ;;
            4)
                check_links
                pause_for_user
                ;;
            5)
                unlink_all
                pause_for_user
                ;;
            6)
                init_repository
                discover_configs
                create_links
                print_success "Complete setup finished!"
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
    
    echo
    print_success "Done! 🎉"
    [[ -d "$BACKUP_DIR" ]] && print_info "Backups: $BACKUP_DIR"
    print_info "Log file: $LOG_FILE"
}

# Run the script
main "$@"
