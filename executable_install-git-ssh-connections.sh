#!/usr/bin/env bash

# ========================
#  Colors
# ========================
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warning() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}==>${RESET}${BOLD} $1${RESET}"; }
pause()   { echo -e "\n${YELLOW}Press ENTER when you are ready to continue...${RESET}"; read -r; }

# ========================
#  GitHub account mode
# single = one GitHub account, standard github.com URL (no alias)
# dual   = personal + work, uses github / github-work aliases
# ========================
GITHUB_MODE="single"

detect_github_mode() {
    if grep -q "github-work" "$HOME/.ssh/config" 2>/dev/null; then
        GITHUB_MODE="dual"
    elif grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
        GITHUB_MODE="single"
    elif [ -f "$HOME/.ssh/id_github_work" ]; then
        GITHUB_MODE="dual"
    else
        GITHUB_MODE="single"
    fi
}
detect_github_mode

# ========================
#  Initial checks
# ========================
check_dependencies() {
    if ! command -v ssh-keygen &>/dev/null; then
        error "ssh-keygen not found. Install openssh first: sudo pacman -S openssh"
    fi
    if ! command -v xclip &>/dev/null && ! command -v wl-copy &>/dev/null; then
        warning "Neither xclip nor wl-copy found. Keys won't be copied to clipboard automatically."
        warning "Install wl-copy with: sudo pacman -S wl-clipboard"
    fi
}

# Copy to clipboard based on environment (X11 or Wayland)
copy_to_clipboard() {
    if command -v wl-copy &>/dev/null; then
        echo "$1" | wl-copy
        success "Key copied to clipboard (Wayland)"
    elif command -v xclip &>/dev/null; then
        echo "$1" | xclip -selection clipboard
        success "Key copied to clipboard (X11)"
    else
        warning "Could not copy to clipboard, please copy it manually"
    fi
}

# ========================
#  Prepare ~/.ssh
# ========================
setup_ssh_dir() {
    step "Preparing ~/.ssh directory"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    success "~/.ssh ready"
}

# ========================
#  Validate no key overlap
# Checks that the email is not already used by another key
# ========================
validate_no_overlap() {
    local email="$1"
    local keyfile_to_skip="$HOME/.ssh/$2"  # the key being created/regenerated (skip it)

    for pubkey in "$HOME"/.ssh/*.pub; do
        [ -f "$pubkey" ] || continue
        # Skip the key we're about to create
        [ "$pubkey" = "$keyfile_to_skip.pub" ] && continue

        if grep -q "$email" "$pubkey" 2>/dev/null; then
            local existing
            existing=$(basename "$pubkey" .pub)
            warning "Email '$email' is already used by key: $existing"
            warning "Using the same email across keys is allowed but means both keys belong to the same account."
            read -rp "  Continue anyway? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                info "Aborted."
                return 1
            fi
        fi
    done
    return 0
}

# ========================
#  Generate SSH key
# ========================
# Args: $1 = filename, $2 = email, $3 = human-readable label
generate_key() {
    local keyfile="$HOME/.ssh/$1"
    local email="$2"
    local label="$3"

    validate_no_overlap "$email" "$1" || return 1

    if [ -f "$keyfile" ]; then
        warning "Key $keyfile already exists, skipping generation"
    else
        info "Generating SSH key for $label..."
        ssh-keygen -t ed25519 -C "$email" -f "$keyfile" -N ""
        success "Key generated: $keyfile"
    fi

    chmod 600 "$keyfile"
    chmod 644 "$keyfile.pub"
}

# Force regenerate — removes existing key first
force_generate_key() {
    local keyfile="$HOME/.ssh/$1"
    local email="$2"
    local label="$3"

    validate_no_overlap "$email" "$1" || return 1

    if [ -f "$keyfile" ]; then
        info "Removing existing key $keyfile..."
        rm -f "$keyfile" "$keyfile.pub"
    fi

    info "Generating new SSH key for $label..."
    ssh-keygen -t ed25519 -C "$email" -f "$keyfile" -N ""
    success "Key generated: $keyfile"

    chmod 600 "$keyfile"
    chmod 644 "$keyfile.pub"
}

# ========================
#  Show public key and wait
# ========================
show_and_wait() {
    local keyfile="$HOME/.ssh/$1.pub"
    local platform="$2"
    local settings_url="$3"
    local pubkey
    pubkey=$(cat "$keyfile")

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  Public key for $platform:${RESET}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "${CYAN}$pubkey${RESET}"
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""

    copy_to_clipboard "$pubkey"

    echo -e "${YELLOW}Steps to follow:${RESET}"
    echo "  1. Open: $settings_url"
    echo "  2. Click 'New SSH key' (or 'Add SSH key')"
    echo "  3. Paste the copied key"
    echo "  4. Save"

    pause
}

# ========================
#  Verify SSH connection
# ========================
verify_connection() {
    local host="$1"
    local label="$2"

    info "Verifying connection with $label..."
    if ssh -T -o StrictHostKeyChecking=no "$host" 2>&1 | grep -qiE "success|welcome|authenticated|hi "; then
        success "Connection with $label verified"
    else
        ssh -T -o StrictHostKeyChecking=no "$host" 2>&1 || true
        warning "Check the message above. If you see your username, everything is fine."
    fi
}

# ========================
#  Write ~/.ssh/config
# ========================
write_ssh_config() {
    step "Writing ~/.ssh/config"
    local config="$HOME/.ssh/config"

    if [ -f "$config" ]; then
        cp "$config" "$config.backup.$(date +%Y%m%d%H%M%S)"
        warning "Backup of previous config saved"
    fi

    if [ "$GITHUB_MODE" = "single" ]; then
        cat > "$config" << EOF
# ========================
#  GitHub (single account)
# Standard github.com URL, no alias needed
# ========================
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_github
    AddKeysToAgent yes

# ========================
#  GitLab
# ========================
Host gitlab
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_gitlab
    AddKeysToAgent yes
EOF
    else
        cat > "$config" << EOF
# ========================
#  GitHub Personal
# ========================
Host github
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_github
    AddKeysToAgent yes

# ========================
#  GitHub Work
# ========================
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_github_work
    AddKeysToAgent yes

# ========================
#  GitLab
# ========================
Host gitlab
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_gitlab
    AddKeysToAgent yes
EOF
    fi

    chmod 600 "$config"
    success "~/.ssh/config created"
}

# ========================
#  Add keys to ssh-agent
# ========================
setup_agent() {
    step "Adding keys to ssh-agent"
    eval "$(ssh-agent -s)" > /dev/null
    for key in id_github id_github_work id_gitlab; do
        if [ -f "$HOME/.ssh/$key" ]; then
            ssh-add "$HOME/.ssh/$key"
            success "$key added to agent"
        fi
    done
}

# ========================
#  Per-account flows
# ========================
setup_github_single() {
    step "GitHub (single account)"
    read -rp "  Email for your GitHub account: " email
    generate_key "id_github" "$email" "GitHub" || return
    show_and_wait "id_github" "GitHub" "https://github.com/settings/ssh/new"
    verify_connection "github.com" "GitHub"
}

setup_github_personal() {
    step "GitHub Personal"
    read -rp "  Email for your personal GitHub account: " email
    generate_key "id_github" "$email" "GitHub Personal" || return
    show_and_wait "id_github" "GitHub Personal" "https://github.com/settings/ssh/new"
    verify_connection "github" "GitHub Personal"
}

setup_github_work() {
    step "GitHub Work"
    read -rp "  Email for your work GitHub account: " email
    generate_key "id_github_work" "$email" "GitHub Work" || return
    show_and_wait "id_github_work" "GitHub Work" "https://github.com/settings/ssh/new"
    verify_connection "github-work" "GitHub Work"
}

setup_gitlab() {
    step "GitLab"
    read -rp "  Email for your GitLab account: " email
    generate_key "id_gitlab" "$email" "GitLab" || return
    show_and_wait "id_gitlab" "GitLab" "https://gitlab.com/-/profile/keys"
    verify_connection "gitlab" "GitLab"
}

# ========================
#  Regenerate flows
# ========================
regenerate_key() {
    local keyname="$1"    # e.g. id_github
    local label="$2"      # e.g. "GitHub Personal"
    local url="$3"        # settings URL
    local host="$4"       # SSH host alias

    step "Regenerate $label key"
    warning "This will DELETE the existing $keyname key and create a new one."
    read -rp "  Are you sure? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    read -rp "  Email for $label: " email
    force_generate_key "$keyname" "$email" "$label" || return
    show_and_wait "$keyname" "$label" "$url"
    write_ssh_config
    setup_agent
    verify_connection "$host" "$label"
    show_summary
}

# ========================
#  Final summary
# ========================
show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}  ✓ SSH setup complete${RESET}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    if [ "$GITHUB_MODE" = "single" ]; then
        echo -e "${BOLD}How to clone repositories:${RESET}"
        echo ""
        echo -e "  ${CYAN}GitHub:${RESET}"
        echo "    git clone git@github.com:youruser/repo.git"
        echo ""
        echo -e "  ${CYAN}GitLab:${RESET}"
        echo "    git clone git@gitlab:company/repo.git"
        echo ""
        echo -e "${YELLOW}Note: on GitHub the standard URL is kept, no alias needed.${RESET}"
        echo ""
    else
        echo -e "${BOLD}How to clone repositories:${RESET}"
        echo ""
        echo -e "  ${CYAN}GitHub personal:${RESET}"
        echo "    git clone git@github:youruser/repo.git"
        echo ""
        echo -e "  ${CYAN}GitHub work:${RESET}"
        echo "    git clone git@github-work:company/repo.git"
        echo ""
        echo -e "  ${CYAN}GitLab:${RESET}"
        echo "    git clone git@gitlab:company/repo.git"
        echo ""
        echo -e "${YELLOW}Note: use the Host alias (github, github-work, gitlab)${RESET}"
        echo -e "${YELLOW}instead of github.com or gitlab.com when cloning.${RESET}"
        echo ""
    fi
}

# ========================
#  Main menu
# ========================
while true; do
    echo ""
    echo "==============================="
    echo "   SSH Setup"
    echo "==============================="
    echo "── Setup ───────────────────────"
    echo "1) GitHub (single account, standard URL)"
    echo "2) GitHub Personal"
    echo "3) GitHub Work"
    echo "4) GitLab"
    echo "5) All (3 accounts)"
    echo "── Regenerate ──────────────────"
    echo "6) Regenerate GitHub key (single)"
    echo "7) Regenerate GitHub Personal key"
    echo "8) Regenerate GitHub Work key"
    echo "9) Regenerate GitLab key"
    echo "0) Exit"
    echo ""
    read -rp "Choose an option: " option

    case $option in
        1)
            check_dependencies
            setup_ssh_dir
            GITHUB_MODE="single"
            setup_github_single
            write_ssh_config
            setup_agent
            show_summary
            ;;
        2)
            check_dependencies
            setup_ssh_dir
            GITHUB_MODE="dual"
            setup_github_personal
            write_ssh_config
            setup_agent
            show_summary
            ;;
        3)
            check_dependencies
            setup_ssh_dir
            GITHUB_MODE="dual"
            setup_github_work
            write_ssh_config
            setup_agent
            show_summary
            ;;
        4)
            check_dependencies
            setup_ssh_dir
            setup_gitlab
            write_ssh_config
            setup_agent
            show_summary
            ;;
        5)
            check_dependencies
            setup_ssh_dir
            GITHUB_MODE="dual"
            setup_github_personal
            setup_github_work
            setup_gitlab
            write_ssh_config
            setup_agent
            show_summary
            ;;
        6)
            check_dependencies
            setup_ssh_dir
            GITHUB_MODE="single"
            regenerate_key "id_github" "GitHub" "https://github.com/settings/ssh/new" "github.com"
            ;;
        7)
            check_dependencies
            setup_ssh_dir
            GITHUB_MODE="dual"
            regenerate_key "id_github" "GitHub Personal" "https://github.com/settings/ssh/new" "github"
            ;;
        8)
            check_dependencies
            setup_ssh_dir
            GITHUB_MODE="dual"
            regenerate_key "id_github_work" "GitHub Work" "https://github.com/settings/ssh/new" "github-work"
            ;;
        9)
            check_dependencies
            setup_ssh_dir
            regenerate_key "id_gitlab" "GitLab" "https://gitlab.com/-/profile/keys" "gitlab"
            ;;
        0) echo ""; echo "Bye!"; break ;;
        *) warning "Invalid option, choose between 0 and 9" ;;
    esac
done
