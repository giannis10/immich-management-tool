#!/bin/bash

# ==============================================================================
# Immich Management Tool (Auto-Update, Backup, and Rollback)
# Created by: G.T
# ==============================================================================

# Define the configuration file path (stored in the same directory as this script)
CONFIG_FILE="$(dirname "$(readlink -f "$0")")/immich_update.conf"
BACKUP_PREFIX="immich_backup_"

# Enforce root privileges - required for Docker commands and file permissions
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script as root or using sudo."
  exit 1
fi

# --- FUNCTION: Detect Docker Compose command ---
detect_docker_compose() {
    if docker compose version &>/dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        echo "❌ Error: Neither 'docker compose' (v2) nor 'docker-compose' (v1) was found."
        echo "   Please install Docker Compose and try again."
        exit 1
    fi
}

# --- FUNCTION: Initial Setup Wizard ---
run_setup_wizard() {
    clear
    echo "===================================================="
    echo "🔧 Setup Wizard"
    echo "===================================================="
    echo ""

    SOURCE_DIR=""
    
    # Ask the user if they want to attempt auto-discovery of the Immich path
    read -p "🔍 Do you want to auto-scan for your Immich installation? (Y/n): " do_scan
    do_scan=${do_scan:-Y}

    if [[ "$do_scan" =~ ^[Yy]$ ]]; then
        echo "⏳ Scanning Docker for running Immich containers..."
        
        # Look for a running Immich container and extract its working directory via compose labels
        IMMICH_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i immich | head -n 1)
        if [ -n "$IMMICH_CONTAINER" ]; then
            SOURCE_DIR=$(docker inspect "$IMMICH_CONTAINER" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}')
        fi

        # Validate the discovered path
        if [ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ]; then
            echo "✅ Found Immich directory at: $SOURCE_DIR"
            read -p "Is this correct? (Y/n): " path_correct
            path_correct=${path_correct:-Y}
            if [[ ! "$path_correct" =~ ^[Yy]$ ]]; then
                SOURCE_DIR="" 
            fi
        else
            echo "⚠️ Could not automatically detect the Immich directory (Is Immich currently running?)."
        fi
    fi

    # Fallback to manual path entry if auto-scan fails or is skipped by the user
    while [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; do
        read -p "📁 Please enter the FULL PATH to your Immich directory (where docker-compose.yml is): " SOURCE_DIR
        if [ ! -d "$SOURCE_DIR" ]; then
            echo "❌ Directory does not exist. Please try again."
            SOURCE_DIR=""
        fi
    done

    # Set up backup destination with a sensible default
    DEFAULT_BACKUP="/var/backups/immich"
    read -p "📦 Where should backups be saved? [Default: $DEFAULT_BACKUP]: " BACKUP_ROOT
    BACKUP_ROOT=${BACKUP_ROOT:-$DEFAULT_BACKUP}

    # Define backup retention policy
    DEFAULT_RETAIN=2
    read -p "🧹 How many old backups do you want to keep automatically? [Default: $DEFAULT_RETAIN]: " RETAIN_BACKUPS
    RETAIN_BACKUPS=${RETAIN_BACKUPS:-$DEFAULT_RETAIN}

    # Save preferences to the local config file for future runs
    echo ""
    read -p "💾 Save these settings and overwrite previous configuration? (y/N): " confirm_save
    confirm_save=${confirm_save:-y}

    if [[ "$confirm_save" =~ ^[Yy]$ ]]; then
        cat <<EOF > "$CONFIG_FILE"
SOURCE_DIR="$SOURCE_DIR"
BACKUP_ROOT="$BACKUP_ROOT"
RETAIN_BACKUPS=$RETAIN_BACKUPS
EOF
        echo "✅ Setup complete and saved!"
    else
        echo "❌ Setup cancelled. Changes were not saved."
    fi
    sleep 2
}

# --- FUNCTION: Execute Backup and Update Process ---
perform_update() {
    echo ""
    echo "===================================================="
    echo "🚀 Update Immich"
    echo "===================================================="
    
    # Final sanity check before starting the update process
    read -p "❓ Ready to create a backup and update Immich? (y/N): " confirm_update
    confirm_update=${confirm_update:-N}
    
    if [[ ! "$confirm_update" =~ ^[Yy]$ ]]; then
        echo "❌ Update cancelled."
        read -p "Press Enter to return to menu..."
        return
    fi

    CURRENT_DATE=$(date +%d-%m-%Y_%H-%M-%S)
    BACKUP_NAME="${BACKUP_PREFIX}${CURRENT_DATE}"

    echo "----------------------------------------------------"
    
    cd "$SOURCE_DIR" || exit
    
    # Stop containers gracefully to prevent database corruption
    echo "🛑 Stopping containers gracefully..."
    $DOCKER_COMPOSE down

    # Ensure the backup directory exists
    if [ ! -d "$BACKUP_ROOT" ]; then
        mkdir -p "$BACKUP_ROOT"
    fi

    # Perform the actual backup (using -a to preserve attributes, omitting -v to prevent terminal spam)
    echo "📦 Creating backup: $BACKUP_NAME..."
    if cp -a "$SOURCE_DIR" "$BACKUP_ROOT/$BACKUP_NAME"; then
        echo "✅ Backup created successfully."
    else
        echo "❌ Error: Backup failed! Aborting update to protect existing data."
        read -p "Press Enter to return to menu..."
        return
    fi

    # Handle backup rotation based on user's retention policy
    echo "🧹 Cleaning up old backups (Keeping the latest $RETAIN_BACKUPS)..."
    cd "$BACKUP_ROOT" || exit
    ls -td ${BACKUP_PREFIX}* 2>/dev/null | tail -n +$((RETAIN_BACKUPS + 1)) | while read -r old_backup; do
        echo "🗑️ Auto-deleting old backup: $old_backup"
        rm -rf "$old_backup"
    done

    # Pull the latest images and bring the stack back up
    echo "🔄 Pulling latest images and starting containers..."
    cd "$SOURCE_DIR" || exit
    $DOCKER_COMPOSE pull
    $DOCKER_COMPOSE up -d

    echo "🎉 Immich successfully updated!"
    read -p "Press Enter to return to menu..."
}

# --- FUNCTION: Restore/Rollback from an existing backup ---
restore_backup() {
    echo ""
    echo "===================================================="
    echo "⏪ Restore a Previous Backup"
    echo "===================================================="
    
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "❌ Backup directory not found."
        read -p "Press Enter to return..."
        return
    fi

    cd "$BACKUP_ROOT" || exit
    
    # Fetch all available backups, sorted by newest first, and store them in an array
    mapfile -t BACKUPS < <(ls -dt ${BACKUP_PREFIX}* 2>/dev/null)

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "⚠️ No backups found to restore."
        read -p "Press Enter to return..."
        return
    fi

    # Display available backups as a numbered list
    echo "Available backups:"
    for i in "${!BACKUPS[@]}"; do
        echo "$((i+1))) ${BACKUPS[$i]}"
    done
    echo "0) Cancel"

    read -p "Select a backup to restore [0-$(( ${#BACKUPS[@]} ))]: " choice

    if [[ "$choice" -eq 0 ]]; then
        return
    elif [[ "$choice" -gt 0 && "$choice" -le "${#BACKUPS[@]}" ]]; then
        SELECTED_BACKUP="${BACKUPS[$((choice-1))]}"
        
        echo "⚠️ WARNING: This will overwrite your current Immich installation at $SOURCE_DIR!"
        read -p "❓ Are you absolutely sure? (Type YES to confirm): " confirm
        
        if [ "$confirm" = "YES" ]; then
            echo "🛑 Stopping current containers..."
            cd "$SOURCE_DIR" && $DOCKER_COMPOSE down
            
            echo "🗑️ Removing current corrupted/old files..."
            rm -rf "$SOURCE_DIR"
            
            echo "⏪ Restoring from $SELECTED_BACKUP..."
            cp -a "$BACKUP_ROOT/$SELECTED_BACKUP" "$SOURCE_DIR"
            
            echo "▶️ Starting restored containers..."
            cd "$SOURCE_DIR" && $DOCKER_COMPOSE up -d
            echo "✅ Restore completed successfully!"
        else
            echo "❌ Restore cancelled."
        fi
    else
        echo "❌ Invalid choice."
    fi
    read -p "Press Enter to return to menu..."
}

# --- FUNCTION: Manual Backup Management ---
manage_backups() {
    echo ""
    echo "===================================================="
    echo "🗑️ Manage Backups"
    echo "===================================================="
    
    cd "$BACKUP_ROOT" 2>/dev/null || { echo "❌ Backup directory not found."; read -p "Press Enter..."; return; }
    
    mapfile -t BACKUPS < <(ls -dt ${BACKUP_PREFIX}* 2>/dev/null)

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "⚠️ No backups found."
        read -p "Press Enter to return..."
        return
    fi

    echo "Available backups:"
    for i in "${!BACKUPS[@]}"; do
        echo "$((i+1))) ${BACKUPS[$i]}"
    done
    echo "0) Cancel"

    read -p "Select a backup to DELETE [0-$(( ${#BACKUPS[@]} ))]: " choice

    if [[ "$choice" -eq 0 ]]; then
        return
    elif [[ "$choice" -gt 0 && "$choice" -le "${#BACKUPS[@]}" ]]; then
        SELECTED_BACKUP="${BACKUPS[$((choice-1))]}"
        
        # Extra safety layer: explicit confirmation before permanent deletion
        read -p "❓ Are you sure you want to PERMANENTLY delete '$SELECTED_BACKUP'? (y/N): " confirm_delete
        confirm_delete=${confirm_delete:-N}
        
        if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
            echo "🗑️ Deleting $SELECTED_BACKUP..."
            rm -rf "$SELECTED_BACKUP"
            echo "✅ Backup deleted."
        else
            echo "❌ Deletion cancelled."
        fi
    else
        echo "❌ Invalid choice."
    fi
    read -p "Press Enter to return to menu..."
}

# --- MAIN ENTRY POINT ---

# Detect which Docker Compose command is available on this system
detect_docker_compose

# Trigger the setup wizard if no config file is found
if [ ! -f "$CONFIG_FILE" ]; then
    run_setup_wizard
fi

# Load saved user variables
source "$CONFIG_FILE"

# Main interactive menu loop
while true; do
    clear
    echo "===================================================="
    echo "   🌟 IMMICH MANAGEMENT TOOL 🌟"
    echo "             Created by G.T"
    echo "===================================================="
    echo "   📍 Path: $SOURCE_DIR"
    echo "   📦 Backups: $BACKUP_ROOT"
    echo "   🐳 Docker Compose: $DOCKER_COMPOSE"
    echo "===================================================="
    echo "1) 🚀 Update Immich (Auto-Backup & Update)"
    echo "2) ⏪ Restore from Backup (Rollback)"
    echo "3) 🗑️ Delete a specific Backup"
    echo "4) ⚙️ Change Settings (Run Setup Again)"
    echo "5) ❌ Exit"
    echo "===================================================="
    read -p "👉 Choose an option [1-5]: " MENU_CHOICE

    case $MENU_CHOICE in
        1) perform_update ;;
        2) restore_backup ;;
        3) manage_backups ;;
        4) run_setup_wizard; source "$CONFIG_FILE" ;;
        5) echo "Goodbye!"; exit 0 ;;
        *) echo "❌ Invalid option!"; sleep 1 ;;
    esac
done
