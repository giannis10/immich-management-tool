#!/bin/bash

# ==============================================================================
# Immich Management Tool (Ultimate Safety Edition)
# Created by: G.T | Features: Full Migration, Space Check, Auto-Rollback
# ==============================================================================

CONFIG_FILE="$(dirname "$(readlink -f "$0")")/immich_update.conf"
BACKUP_PREFIX="immich_backup_"

# ------------------------------------------------------------------------------
# Colour helpers
# ------------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}   ℹ️  $*${RESET}"; }
success() { echo -e "${GREEN}   ✅ $*${RESET}"; }
warning() { echo -e "${YELLOW}   ⚠️  $*${RESET}"; }
error()   { echo -e "${RED}   ❌ $*${RESET}"; }
section() { echo ""; echo "----------------------------------------------------"; echo -e "${BOLD}$*${RESET}"; echo "----------------------------------------------------"; }
desc()    { echo -e "${CYAN}📝 DESCRIPTION:${RESET}"; echo -e "   $1"; echo ""; }

# Enforce root privileges
if [ "$EUID" -ne 0 ]; then
  error "Please run this script as root or using sudo."
  exit 1
fi

# ==============================================================================
# --- FUNCTION: Version Check ---
# ==============================================================================
get_current_version() {
    # Try to get version from running immich-server container
    local version=""
    
    # Method 1: Read from container environment variable
    local container
    container=$(docker ps --format '{{.Names}}' | grep -i 'immich.server\|immich-server' | head -n 1)
    if [ -z "$container" ]; then
        container=$(docker ps --format '{{.Names}}' | grep -i 'immich' | grep -v 'postgres\|redis\|machine' | head -n 1)
    fi

    if [ -n "$container" ]; then
        version=$(docker exec "$container" printenv IMMICH_VERSION 2>/dev/null)
        if [ -z "$version" ]; then
            # Method 2: Read from Docker image tag
            version=$(docker inspect "$container" --format '{{.Config.Image}}' 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        fi
        if [ -z "$version" ]; then
            # Method 3: Read from image labels
            version=$(docker inspect "$container" --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null)
        fi
    fi

    # Method 4: Read from .env file in SOURCE_DIR
    if [ -z "$version" ] && [ -f "$SOURCE_DIR/.env" ]; then
        version=$(grep -E '^IMMICH_VERSION=' "$SOURCE_DIR/.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        [ "$version" = "release" ] || [ "$version" = "" ] && version=""
    fi

    # Method 5: Read from docker-compose.yml image tag
    if [ -z "$version" ] && [ -f "$SOURCE_DIR/docker-compose.yml" ]; then
        version=$(grep -oE 'ghcr\.io/immich-app/immich-server:v[0-9]+\.[0-9]+\.[0-9]+' "$SOURCE_DIR/docker-compose.yml" 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi

    echo "${version:-unknown}"
}

get_latest_version() {
    # Fetch latest release tag from GitHub API
    local latest=""
    if command -v curl &>/dev/null; then
        latest=$(curl -sf --max-time 10 \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/immich-app/immich/releases/latest" \
            | grep -oE '"tag_name":\s*"v[^"]*"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    elif command -v wget &>/dev/null; then
        latest=$(wget -qO- --timeout=10 \
            "https://api.github.com/repos/immich-app/immich/releases/latest" \
            | grep -oE '"tag_name":\s*"v[^"]*"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi
    echo "${latest:-unknown}"
}

check_versions() {
    clear
    section "🔍 Immich Version Check"
    desc "Checks your currently installed Immich version and the latest available release on GitHub."

    info "Detecting installed version..."
    local current
    current=$(get_current_version)

    info "Fetching latest version from GitHub..."
    local latest
    latest=$(get_latest_version)

    echo ""
    echo "===================================================="
    if [ "$current" = "unknown" ]; then
        echo -e "  📦 Installed Version : ${YELLOW}Could not detect${RESET}"
        warning "Immich may not be running, or the container name is non-standard."
    else
        echo -e "  📦 Installed Version : ${CYAN}${BOLD}$current${RESET}"
    fi

    if [ "$latest" = "unknown" ]; then
        echo -e "  🌐 Latest Version    : ${YELLOW}Could not fetch (no internet?)${RESET}"
    else
        echo -e "  🌐 Latest Version    : ${GREEN}${BOLD}$latest${RESET}"
    fi
    echo "===================================================="

    # Compare versions and give advice
    if [ "$current" != "unknown" ] && [ "$latest" != "unknown" ]; then
        echo ""
        # Strip 'v' prefix for comparison
        local cur_clean="${current#v}"
        local lat_clean="${latest#v}"

        if [ "$cur_clean" = "$lat_clean" ]; then
            success "You are already on the latest version! ✨"
        else
            # Simple semver comparison using sort -V
            local older
            older=$(printf '%s\n%s' "$cur_clean" "$lat_clean" | sort -V | head -n 1)
            if [ "$older" = "$cur_clean" ]; then
                echo -e "  ${YELLOW}⬆️  An update is available: ${BOLD}$current${RESET}${YELLOW} → ${BOLD}$latest${RESET}"
                echo ""
                read -p "   Would you like to update now? (y/N): " do_update
                if [[ "$do_update" =~ ^[Yy]$ ]]; then
                    perform_update
                    return
                fi
            else
                warning "Your version ($current) appears newer than the latest release ($latest)."
                info "You may be running a release candidate or custom build."
            fi
        fi
    fi

    echo ""
    read -p "Press Enter to return to menu..."
}

# --- FUNCTION: Detect Docker Compose command ---
detect_docker_compose() {
    if docker compose version &>/dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        error "Docker Compose was not found. Please install it first."
        exit 1
    fi
}

# ==============================================================================
# --- FUNCTION: Initial Setup Wizard ---
# ==============================================================================
run_setup_wizard() {
    clear
    section "🔧 Setup Wizard"
    desc "This wizard helps the script learn where your Immich installation is located and where you want to store your backups."

    SOURCE_DIR=""
    read -p "🔍 Auto-scan for Immich? (Y/n): " do_scan
    do_scan=${do_scan:-Y}
    if [[ "$do_scan" =~ ^[Yy]$ ]]; then
        info "Scanning Docker for running Immich containers..."
        IMMICH_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i immich | head -n 1)
        if [ -n "$IMMICH_CONTAINER" ]; then
            SOURCE_DIR=$(docker inspect "$IMMICH_CONTAINER" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}')
        fi

        if [ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ]; then
            success "Found Immich directory at: $SOURCE_DIR"
            read -p "Is this correct? (Y/n): " path_correct
            path_correct=${path_correct:-Y}
            [[ ! "$path_correct" =~ ^[Yy]$ ]] && SOURCE_DIR=""
        else
            warning "Could not automatically detect the Immich directory."
        fi
    fi

    while [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; do
        read -p "📁 Enter the FULL PATH to your Immich directory (where docker-compose.yml is): " SOURCE_DIR
        [ ! -d "$SOURCE_DIR" ] && error "Directory does not exist." && SOURCE_DIR=""
    done

    read -p "📦 Where should backups be saved? [/var/backups/immich]: " BACKUP_ROOT
    BACKUP_ROOT=${BACKUP_ROOT:-/var/backups/immich}

    while true; do
        read -p "🧹 How many old backups should I keep? [2]: " RETAIN_BACKUPS
        RETAIN_BACKUPS=${RETAIN_BACKUPS:-2}
        [[ "$RETAIN_BACKUPS" =~ ^[1-9][0-9]*$ ]] && break || error "Enter a valid number."
    done

    cat <<EOF > "$CONFIG_FILE"
SOURCE_DIR="$SOURCE_DIR"
BACKUP_ROOT="$BACKUP_ROOT"
RETAIN_BACKUPS=$RETAIN_BACKUPS
EOF
    success "Settings saved successfully!"
    sleep 2
}

# ==============================================================================
# --- FUNCTION: Update Process ---
# ==============================================================================
perform_update() {
    section "🚀 Update Immich"
    desc "Downloads the latest version. Creates an automatic backup before starting."

    cd "$SOURCE_DIR" || { error "Access denied."; return; }
    read -p "❓ Proceed with the update? (y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    info "Stopping containers..."
    $DOCKER_COMPOSE down

    [ ! -d "$BACKUP_ROOT" ] && mkdir -p "$BACKUP_ROOT"

    local bkp="$BACKUP_ROOT/${BACKUP_PREFIX}$(date +%Y%m%d_%H%M%S)"
    info "Creating backup at $bkp..."
    mkdir -p "$bkp"

    if cp -a "$SOURCE_DIR/." "$bkp/"; then
        success "Backup created."
    else
        error "Backup failed! Aborting."
        $DOCKER_COMPOSE up -d
        read -p "Press Enter..."; return
    fi

    info "Cleaning up old backups..."
    cd "$BACKUP_ROOT" || exit
    ls -td ${BACKUP_PREFIX}* 2>/dev/null | tail -n +$((RETAIN_BACKUPS + 1)) | xargs rm -rf 2>/dev/null

    cd "$SOURCE_DIR" || exit
    info "Pulling latest images..."
    if $DOCKER_COMPOSE pull; then
        $DOCKER_COMPOSE up -d
        success "Update successful!"
    else
        error "Pull failed. Restoring previous version..."
        cp -a "$bkp/." "$SOURCE_DIR/"
        $DOCKER_COMPOSE up -d
    fi
    read -p "Press Enter..."
}

# ==============================================================================
# --- FUNCTION: Full Migration with Space Check ---
# ==============================================================================
migrate_data() {
    clear
    section "💾 Full Migration (New Disk/Path)"
    desc "Moves EVERYTHING to a new disk. Includes a pre-flight space check."

    warning "CRITICAL: The new disk MUST be formatted as ext4, xfs, or zfs."
    read -p "❓ Start the migration? (y/N): " proceed
    [[ ! "$proceed" =~ ^[Yy]$ ]] && return

    read -p "📁 Enter the FULL PATH for the NEW location (e.g., /mnt/newdisk/immich): " NEW_PROJECT_DIR
    [ -z "$NEW_PROJECT_DIR" ] && return
    
    if [ "$(realpath "$NEW_PROJECT_DIR" 2>/dev/null)" = "$(realpath "$SOURCE_DIR")" ]; then
        error "New path is the same as current path!"
        read -p "Press Enter..."; return
    fi

    # --- DISK SPACE CHECK ---
    section "📊 Step 0: Disk Space Check"
    info "Calculating source size and available space..."
    
    # Get source size in KB
    local source_size_kb=$(du -sk "$SOURCE_DIR" | awk '{print $1}')
    
    # Create destination parent if it doesn't exist to check space correctly
    mkdir -p "$NEW_PROJECT_DIR"
    
    # Get available space on destination in KB
    local dest_free_kb=$(df -Pk "$NEW_PROJECT_DIR" | awk 'NR==2 {print $4}')
    
    # Convert to Human Readable for display
    local source_human=$(du -sh "$SOURCE_DIR" | awk '{print $1}')
    local dest_human=$(df -h "$NEW_PROJECT_DIR" | awk 'NR==2 {print $4}')

    info "Source Data Size : $source_human"
    info "Available Space  : $dest_human"

    if [ "$source_size_kb" -gt "$dest_free_kb" ]; then
        echo ""
        error "INSUFFICIENT DISK SPACE!"
        error "You need at least $source_human, but only $dest_human is available."
        error "Migration aborted to prevent data corruption."
        read -p "Press Enter to return to menu..."
        return
    fi
    success "Space check passed. Proceeding..."

    section "🛑 Step 1: Preparation & Database Dump"
    info "Stopping Immich..."
    cd "$SOURCE_DIR" || exit
    $DOCKER_COMPOSE down

    local db_container=$(docker ps -a --format '{{.Names}}' | grep -i 'postgres' | head -n 1)
    if [ -n "$db_container" ]; then
        info "Exporting database dump..."
        docker start "$db_container" && sleep 5
        docker exec "$db_container" pg_dumpall -U postgres > "$NEW_PROJECT_DIR/emergency_db_backup.sql"
        docker stop "$db_container"
        success "DB exported."
    fi

    section "🔄 Step 2: Transferring Data"
    local date_suffix=$(date +%Y%m%d)
    [ -f ".env" ] && cp ".env" ".env.migbak_${date_suffix}"
    [ -f "docker-compose.yml" ] && cp "docker-compose.yml" "docker-compose.yml.migbak_${date_suffix}"
    
    info "Copying files (this may take a long time)..."
    if rsync -a --info=progress2 --checksum "$SOURCE_DIR/" "$NEW_PROJECT_DIR/"; then
        success "Files transferred."
    else
        error "Transfer failed! Check disk connection."
        read -p "Press Enter..."; return
    fi

    section "⚙️ Step 3: Updating Paths"
    [ -f "$NEW_PROJECT_DIR/.env" ] && sed -i "s|$SOURCE_DIR|$NEW_PROJECT_DIR|g" "$NEW_PROJECT_DIR/.env"
    sed -i "s|SOURCE_DIR=.*|SOURCE_DIR=\"$NEW_PROJECT_DIR\"|" "$CONFIG_FILE"
    
    section "▶️ Step 4: Launching"
    cd "$NEW_PROJECT_DIR" || exit
    $DOCKER_COMPOSE up -d
    
    success "Migration successful! Immich is running from $NEW_PROJECT_DIR"
    warning "Verify everything before deleting old data at $SOURCE_DIR."
    
    source "$CONFIG_FILE"
    read -p "Press Enter..."
}

# ==============================================================================
# --- OTHER FUNCTIONS ---
# ==============================================================================
restore_backup() {
    section "⏪ Restore Backup"
    [ ! -d "$BACKUP_ROOT" ] && { error "No backups."; return; }
    cd "$BACKUP_ROOT" || exit
    mapfile -t BACKUPS < <(ls -dt ${BACKUP_PREFIX}* 2>/dev/null)
    [ ${#BACKUPS[@]} -eq 0 ] && { error "No backups."; return; }
    
    for i in "${!BACKUPS[@]}"; do echo "   $((i+1))) ${BACKUPS[$i]}"; done
    read -p "👉 Selection [0 for cancel]: " choice
    if [[ "$choice" -gt 0 && "$choice" -le "${#BACKUPS[@]}" ]]; then
        local SEL="${BACKUPS[$((choice-1))]}"
        read -p "Confirm overwrite? (Type YES): " conf
        if [ "$conf" = "YES" ]; then
            cd "$SOURCE_DIR" && $DOCKER_COMPOSE down
            rm -rf "${SOURCE_DIR:?}"/*
            cp -a "$BACKUP_ROOT/$SEL/." "$SOURCE_DIR/"
            $DOCKER_COMPOSE up -d
            success "Restored."
        fi
    fi
    read -p "Press Enter..."
}

manual_migration_undo() {
    section "🆘 Emergency Undo"
    local env_bak=$(ls -t "$SOURCE_DIR"/.env.migbak_* 2>/dev/null | head -n 1)
    if [ -n "$env_bak" ]; then
        read -p "Rollback to old path? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            cd "$SOURCE_DIR" && $DOCKER_COMPOSE down
            cp "$env_bak" .env
            $DOCKER_COMPOSE up -d
            success "Rollback complete."
        fi
    else
        error "No recovery files."
    fi
    read -p "Press Enter..."
}

# ==============================================================================
# --- MAIN MENU ---
# ==============================================================================
detect_docker_compose
[ ! -f "$CONFIG_FILE" ] && run_setup_wizard
source "$CONFIG_FILE"

while true; do
    clear
    echo "===================================================="
    echo -e "${BOLD}    🌟 IMMICH MANAGEMENT TOOL 🌟${RESET}"
    echo "             Created by G.T"
    echo "===================================================="
    echo -e "  📍 Location : ${CYAN}$SOURCE_DIR${RESET}"
    echo -e "  📦 Backups  : ${CYAN}$BACKUP_ROOT${RESET}"

    # --- Inline version display in menu ---
    CURRENT_VER=$(get_current_version)
    LATEST_VER=$(get_latest_version)
    if [ "$CURRENT_VER" = "unknown" ]; then
        echo -e "  🔖 Version  : ${YELLOW}Not detected${RESET}"
    elif [ "$LATEST_VER" != "unknown" ] && [ "${CURRENT_VER#v}" != "${LATEST_VER#v}" ]; then
        OLDER=$(printf '%s\n%s' "${CURRENT_VER#v}" "${LATEST_VER#v}" | sort -V | head -n 1)
        if [ "$OLDER" = "${CURRENT_VER#v}" ]; then
            echo -e "  🔖 Version  : ${YELLOW}$CURRENT_VER${RESET} ${YELLOW}(update available: ${BOLD}$LATEST_VER${RESET}${YELLOW})${RESET}"
        else
            echo -e "  🔖 Version  : ${CYAN}$CURRENT_VER${RESET} ${GREEN}(newer than release)${RESET}"
        fi
    else
        echo -e "  🔖 Version  : ${GREEN}$CURRENT_VER${RESET} ${GREEN}(up to date)${RESET}"
    fi

    echo "===================================================="
    echo "1) 🚀 Update Immich"
    echo "2) ⏪ Restore from Backup"
    echo "3) 💾 Full Migration (New Disk/Path)"
    echo "4) 🆘 Emergency Undo"
    echo "5) 🔍 Version Check"
    echo "6) ⚙️  Settings / Re-run Setup"
    echo "7) ❌ Exit"
    echo "===================================================="
    read -p "👉 Choice [1-7]: " CHOICE

    case $CHOICE in
        1) perform_update ;;
        2) restore_backup ;;
        3) migrate_data ;;
        4) manual_migration_undo ;;
        5) check_versions ;;
        6) run_setup_wizard; source "$CONFIG_FILE" ;;
        7) exit 0 ;;
        *) sleep 1 ;;
    esac
done
