#!/usr/bin/env bash
set -e

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

# ========================
#  Install PostgreSQL
# ========================
install_postgres() {
    step "Installing PostgreSQL"

    if pacman -Qi postgresql &>/dev/null; then
        warning "PostgreSQL is already installed, skipping"
    else
        info "Installing postgresql..."
        sudo pacman -S --noconfirm postgresql
        success "PostgreSQL installed"
    fi
}

# ========================
#  Initialize database
# ========================
init_postgres() {
    step "Initializing PostgreSQL database"

    if [ -f "/var/lib/postgres/data/PG_VERSION" ]; then
        warning "Database already initialized, skipping"
    else
        info "Initializing database cluster..."
        sudo -iu postgres initdb -D /var/lib/postgres/data
        success "Database initialized"
    fi
}

# ========================
#  Enable and start service
# ========================
start_postgres() {
    step "Starting PostgreSQL service"
    sudo systemctl enable --now postgresql
    systemctl is-active --quiet postgresql && success "PostgreSQL is running" || error "PostgreSQL failed to start"
}

# ========================
#  Create development database
# ========================
create_dev_db() {
    step "Creating 'development' database"

    if sudo -iu postgres psql -lqt | cut -d \| -f 1 | grep -qw development; then
        warning "Database 'development' already exists, skipping"
    else
        info "Creating database..."
        sudo -iu postgres createdb development
        success "Database 'development' created"
    fi
}

# ========================
#  Set postgres password
# ========================
set_password() {
    step "Setting postgres user password"
    sudo -u postgres psql -c "ALTER USER postgres PASSWORD '1234';"
    success "Password set to: 1234"
}

# ========================
#  Restore from .backup file
# ========================
restore_backup() {
    step "Restore database from .backup file"
    echo ""
    read -rp "Database name to restore into: " dbname
    read -rp "Full path to .backup file: " backupfile

    if [ ! -f "$backupfile" ]; then
        error "File not found: $backupfile"
    fi

    # Create db if it doesn't exist
    if ! sudo -iu postgres psql -lqt | cut -d \| -f 1 | grep -qw "$dbname"; then
        info "Creating database '$dbname'..."
        sudo -iu postgres createdb "$dbname"
    fi

    info "Restoring $backupfile into $dbname..."
    pg_restore -d "$dbname" -U postgres -v "$backupfile"
    success "Restore complete"
}

# ========================
#  Configure for Docker access
# ========================
configure_docker_access() {
    step "Configuring PostgreSQL for Docker access"

    local PG_CONF="/var/lib/postgres/data/postgresql.conf"
    local PG_HBA="/var/lib/postgres/data/pg_hba.conf"

    # postgresql.conf
    if grep -q "listen_addresses = '\*'" "$PG_CONF" 2>/dev/null; then
        warning "listen_addresses already set to '*', skipping"
    else
        info "Setting listen_addresses = '*'..."
        sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
        success "listen_addresses updated"
    fi

    # pg_hba.conf
    if grep -q "172.17.0.0/16" "$PG_HBA" 2>/dev/null; then
        warning "Docker network rules already present in pg_hba.conf, skipping"
    else
        info "Adding Docker network rules to pg_hba.conf..."
        sudo tee -a "$PG_HBA" > /dev/null << 'EOF'

# Docker network access
host    all    all    172.17.0.0/16    scram-sha-256
host    all    all    172.18.0.0/16    scram-sha-256
host    all    all    172.17.0.0/16    trust
EOF
        success "Docker network rules added"
    fi

    info "Restarting PostgreSQL..."
    sudo systemctl restart postgresql
    success "PostgreSQL restarted"

    # ufw
    if command -v ufw &>/dev/null; then
        info "Allowing port 5432 in ufw..."
        sudo ufw allow 5432/tcp
        sudo ufw reload
        success "ufw updated"
    fi
}

# ========================
#  Install DB manager
# ========================
install_db_manager() {
    step "Install a database manager (optional)"
    echo ""
    echo "1) DBeaver"
    echo "2) Beekeeper Studio"
    echo "0) Skip"
    echo ""
    read -rp "Choose: " choice

    case $choice in
        1)
            if command -v paru &>/dev/null; then paru -S --noconfirm dbeaver
            elif command -v yay &>/dev/null; then yay -S --noconfirm dbeaver
            else error "No AUR helper found"; fi
            success "DBeaver installed"
            ;;
        2)
            if command -v paru &>/dev/null; then paru -S --noconfirm beekeeper-studio-bin
            elif command -v yay &>/dev/null; then yay -S --noconfirm beekeeper-studio-bin
            else error "No AUR helper found"; fi
            success "Beekeeper Studio installed"
            ;;
        0) info "Skipping DB manager" ;;
        *) warning "Invalid option, skipping" ;;
    esac
}

# ========================
#  Full setup
# ========================
full_setup() {
    install_postgres
    init_postgres
    start_postgres
    create_dev_db
    set_password
    configure_docker_access
}

# ========================
#  Main menu
# ========================
while true; do
    echo ""
    echo "==============================="
    echo "   PostgreSQL Setup"
    echo "==============================="
    echo "1) Full setup        (install + init + start + dev db)"
    echo "2) Configure for Docker access"
    echo "3) Restore from .backup file"
    echo "4) Install DB manager (DBeaver / Beekeeper)"
    echo "5) All"
    echo "0) Exit"
    echo ""
    read -rp "Choose an option: " option

    case $option in
        1) full_setup ;;
        2) configure_docker_access ;;
        3) restore_backup ;;
        4) install_db_manager ;;
        5) full_setup; install_db_manager ;;
        0) echo ""; echo "Bye!"; break ;;
        *) echo -e "${YELLOW}[WARN]${RESET} Invalid option, choose between 0 and 5" ;;
    esac
done
