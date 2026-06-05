# 🌟 Immich Management Tool

A Bash script for automated backup, update, rollback, full disk migration, and **version checking** of your [Immich](https://immich.app/) self-hosted installation running via Docker Compose.

**Created by:** G.T

---

## ✨ Features

- 🔍 **Version Check** — Detects your installed Immich version and compares it against the latest GitHub release in real time.
- 🚀 **Auto-Update** — Stops containers, creates a backup, pulls the latest Docker images, and restarts everything automatically.
- 📦 **Automatic Backup** — Takes a full copy of your Immich directory before every update.
- ⏪ **Rollback / Restore** — Easily roll back to any previous backup if something goes wrong.
- 💾 **Full Migration** — Move your entire Immich installation (photos, config, database) to a new disk or path, with a pre-flight disk space check.
- 🆘 **Emergency Undo** — Instantly revert a failed or interrupted migration back to your original setup.
- 🔎 **Auto-Discovery** — Automatically detects your Immich installation path via Docker labels.
- 🧹 **Backup Rotation** — Automatically removes old backups, keeping only the number you specify.
- 🐳 **Docker Compose v1 & v2** — Auto-detects whether to use `docker compose` or `docker-compose`.
- ⚙️ **Persistent Config** — Saves your settings to a local config file so you don't have to re-enter them every time.

---

## 📋 Requirements

- Linux system with **Bash**
- **Docker** with either:
  - Docker Compose **v2** (`docker compose`) — recommended
  - Docker Compose **v1** (`docker-compose`) — also supported
- **Root / sudo** privileges
- Immich running as a Docker Compose stack
- `curl` or `wget` for version checking (usually pre-installed)
- `rsync` recommended for migration (falls back to `cp` if not available)

---

## 🚀 Installation

1. Clone the repository:

```bash
git clone https://github.com/giannis10/Immich-Management-Tool.git
```

Or download the script directly:

```bash
wget https://raw.githubusercontent.com/giannis10/Immich-Management-Tool/main/immich-management-tool.sh
```

2. Make it executable:

```bash
chmod +x immich-management-tool.sh
```

3. Run it as root:

```bash
sudo ./immich-management-tool.sh
```

The **Setup Wizard** will launch automatically on the first run.

---

## ⚙️ First-Time Setup

On first run, the Setup Wizard will guide you through:

| Step | Description |
|------|-------------|
| **Auto-scan** | Scans running Docker containers to find your Immich directory automatically |
| **Manual path** | If auto-scan fails, enter the path manually (e.g. `/opt/immich`) |
| **Backup location** | Where backups will be stored (default: `/var/backups/immich`) |
| **Retention policy** | How many old backups to keep before auto-deleting (default: `2`) |

Settings are saved to `immich_update.conf` in the same directory as the script.

---

## 🗂️ Menu Overview

Every time the menu loads, it shows a live version status line:

```
====================================================
    🌟 IMMICH MANAGEMENT TOOL 🌟
             Created by G.T
====================================================
  📍 Location : /opt/immich
  📦 Backups  : /var/backups/immich
  🔖 Version  : v1.130.0 (update available: v1.134.0)
====================================================
1) 🚀 Update Immich
2) ⏪ Restore from Backup
3) 💾 Full Migration (New Disk/Path)
4) 🆘 Emergency Undo
5) 🔍 Version Check
6) ⚙️  Settings / Re-run Setup
7) ❌ Exit
====================================================
```

The version line changes colour depending on your status:

| State | Display |
|-------|---------|
| Up to date | `🟢 v1.134.0 (up to date)` |
| Update available | `🟡 v1.130.0 (update available: v1.134.0)` |
| Containers stopped | `🟡 Not detected` |

---

## 📖 Menu Options

### 1 — Update Immich
Performs the full update cycle:
1. Stops all Immich containers
2. Creates a timestamped backup of your Immich directory
3. Rotates old backups according to your retention policy
4. Pulls the latest Docker images
5. Starts containers back up
6. If the pull fails, automatically restores the previous version

### 2 — Restore from Backup
Lists all available backups (newest first) as a numbered menu and lets you choose one to restore. Stops current containers, clears the current installation, and restores the selected backup.

> ⚠️ **This is a destructive operation.** You must type `YES` (in caps) to confirm.

### 3 — Full Migration (New Disk/Path)
Moves your entire Immich installation to a new location. The process:
1. **Pre-flight space check** — calculates source size vs available space on the destination and aborts if there isn't enough room
2. Stops all containers
3. Exports a full PostgreSQL database dump to the new location as an extra safety net
4. Backs up your `.env` and `docker-compose.yml` with a date-stamped copy
5. Transfers all files using `rsync --checksum`
6. Updates all path references in `.env` and the config file automatically
7. Starts Immich from the new location

> ⚠️ **The new disk must be formatted as `ext4`, `xfs`, or `zfs`.** Do **not** use NTFS or exFAT — Docker volumes are not compatible with these filesystems.

### 4 — Emergency Undo (Migration Rollback)
If a migration failed or the terminal closed mid-process, this option detects the backup `.env` file created before the migration and restores it, bringing Immich back online on the original path.

### 5 — Version Check
Opens a dedicated screen that:
- Detects your installed version using 5 fallback methods (container env var → image tag → OCI label → `.env` file → `docker-compose.yml`)
- Fetches the latest release from the [Immich GitHub API](https://api.github.com/repos/immich-app/immich/releases/latest)
- Compares them with proper semver ordering
- Offers to launch the update process immediately if a newer version is found

### 6 — Settings / Re-run Setup
Re-runs the Setup Wizard so you can update the Immich path, backup location, or retention policy.

---

## 📁 Backup Naming

Backups are named using the format:

```
immich_backup_YYYYMMDD_HHMMSS
```

For example:
```
immich_backup_20250614_030000
```

---

## 🔧 Configuration File

The script stores settings in `immich_update.conf` next to the script itself:

```bash
SOURCE_DIR="/opt/immich"
BACKUP_ROOT="/var/backups/immich"
RETAIN_BACKUPS=2
```

You can edit this file manually or use option **6** from the menu.

---

## 💡 Tips

- **Keep at least 2 backups** (`RETAIN_BACKUPS=2`) in case the most recent backup itself is corrupted.
- Backups are **full copies** of your Immich directory — make sure your backup destination has enough free disk space before updating.
- **Before migrating**, verify your new disk is mounted and properly formatted (`ext4`/`xfs`/`zfs`).
- **After migrating**, let Immich run for a few days and confirm everything works before deleting data from the old disk.
- The version check requires internet access to reach the GitHub API. On air-gapped servers it will show `Could not fetch`.

---

## ⚠️ Disclaimer

This script modifies and restarts live Docker services and performs destructive operations (deleting directories). Always verify your backup location has sufficient space and test your restore procedure before relying on it in production.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for full details.
