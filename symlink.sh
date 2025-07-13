#!/usr/bin/env bash

# Dotfiles Bootstrap Script
# This script will symlink your dotfiles from a git repository to your home directory
# It creates backups of existing files before replacing them

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.src/dotfiles}"
BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"
SKIP_PATTERNS=(".git" ".gitignore" "README.md" "LICENSE" "bootstrap.sh" ".DS_Store")

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if item should be skipped
should_skip() {
    local item="$1"
    local basename=$(basename "$item")
    
    for pattern in "${SKIP_PATTERNS[@]}"; do
        if [[ "$basename" == "$pattern" ]]; then
            return 0
        fi
    done
    return 1
}

# Create backup of existing file/directory
backup_existing() {
    local target="$1"
    
    if [[ -e "$target" ]] || [[ -L "$target" ]]; then
        local backup_path="$BACKUP_DIR/$(dirname "${target#$HOME/}")"
        mkdir -p "$backup_path"
        
        log_info "Backing up existing $(basename "$target") to $backup_path"
        mv "$target" "$backup_path/$(basename "$target")"
    fi
}

# Create symlink with proper error handling
create_symlink() {
    local source="$1"
    local target="$2"
    
    # Create parent directory if it doesn't exist
    mkdir -p "$(dirname "$target")"
    
    # Create the symlink
    if ln -s "$source" "$target"; then
        log_success "Linked $(basename "$source") → $target"
    else
        log_error "Failed to link $(basename "$source") → $target"
        return 1
    fi
}

# Process a single file or directory
process_item() {
    local item="$1"
    local relative_path="${item#$DOTFILES_DIR/}"
    local target="$HOME/$relative_path"
    
    # Skip if it's in our skip list
    if should_skip "$item"; then
        log_info "Skipping $relative_path"
        return
    fi
    
    # Handle .config directory specially
    if [[ "$relative_path" == ".config" ]] && [[ -d "$item" ]]; then
        # Process contents of .config directory
        for config_item in "$item"/*; do
            if [[ -e "$config_item" ]]; then
                process_config_item "$config_item"
            fi
        done
    else
        # Regular file or directory
        backup_existing "$target"
        create_symlink "$item" "$target"
    fi
}

# Process items within .config directory
process_config_item() {
    local item="$1"
    local relative_path="${item#$DOTFILES_DIR/}"
    local target="$HOME/$relative_path"
    
    if should_skip "$item"; then
        log_info "Skipping $relative_path"
        return
    fi
    
    backup_existing "$target"
    create_symlink "$item" "$target"
}

# Main bootstrap function
bootstrap() {
    log_info "Starting dotfiles bootstrap..."
    log_info "Dotfiles directory: $DOTFILES_DIR"
    log_info "Backup directory: $BACKUP_DIR"
    
    # Check if dotfiles directory exists
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Dotfiles directory not found: $DOTFILES_DIR"
        exit 1
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Process all top-level items in dotfiles directory
    for item in "$DOTFILES_DIR"/.* "$DOTFILES_DIR"/*; do
        # Skip . and .. directories
        if [[ "$item" == "$DOTFILES_DIR/." ]] || [[ "$item" == "$DOTFILES_DIR/.." ]]; then
            continue
        fi
        
        # Skip if file doesn't exist (handles glob expansion when no matches)
        if [[ ! -e "$item" ]]; then
            continue
        fi
        
        process_item "$item"
    done
    
    log_success "Bootstrap complete!"
    
    # Show backup location if any backups were made
    if [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        log_info "Backups saved to: $BACKUP_DIR"
    else
        # Remove empty backup directory
        rmdir "$BACKUP_DIR" 2>/dev/null || true
    fi
}

# Script entry point
main() {
    cat << EOF
Dotfiles Bootstrap Script
========================
This script will symlink your dotfiles to your home directory.
Existing files will be backed up before being replaced.

EOF

    # Allow user to specify custom dotfiles directory
    if [[ $# -gt 0 ]]; then
        DOTFILES_DIR="$(cd "$1" && pwd)"
    fi
    
    # Confirm before proceeding
    read -p "Proceed with linking dotfiles from $DOTFILES_DIR? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bootstrap
    else
        log_info "Bootstrap cancelled."
        exit 0
    fi
}

# Run main function
main "$@"
