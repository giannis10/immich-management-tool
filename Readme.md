# 🌟 Immich Management Tool

A Bash script for automated backup, update, rollback, and full disk migration of your [Immich](https://immich.app/) self-hosted installation running via Docker Compose.

**Created by:** G.T

---

## ✨ Features

- 🚀 **Auto-Update** — Stops containers, creates a backup, pulls the latest Docker images, and restarts everything automatically.
- 📦 **Automatic Backup** — Takes a full copy of your Immich directory before every update.
- ⏪ **Rollback / Restore** — Easily roll back to any previous backup if something goes wrong.
- 🗑️ **Backup Management** — View, inspect sizes, and manually delete old backups.
- 💾 **Full Migration** — Move your entire Immich installation (photos, config, database) to a new disk or path.
- 🆘 **Emergency Undo** — Instantly revert a failed or interrupted migration back to your original setup.
- 🔍 **Auto-Discovery** — Automatically detects your Immich installation path via Docker labels.
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
| **Validation** | Warns you if no `docker-compose.yml` is found in the given path |
| **Backup location** | Where backups will be stored (default: `/var/backups/immich`) |
| **Retention policy** | How many old backups to keep before auto-deleting (default: `2`) |

Settings are saved to `immich_update.conf` in the same directory as the script.

---

## 🗂️ Menu Options

```
====================================================
    🌟 IMMICH MANAGEMENT TOOL 🌟
====================================================
  📍 Location : /opt/immich
  📦 Backups  : /var/backups/immich
  🐳 Compose  : docker compose
====================================================
1) 🚀 Update Immich (Pull & Restart)
2) ⏪ Restore from Backup (Rollback Update)
3) 🗑️  Manage Backup Files
4) 💾 Full Migration (Move to New Disk/Path)
5) 🆘 Emergency Undo (Undo Failed Migration)
6) ⚙️  Settings (Re-run Setup)
7) ❌ Exit
====================================================
```

### 1 — Update Immich
Performs the full update cycle:
1. Stops all Immich containers
2. Creates a timestamped backup of your Immich directory
3. Rotates old backups according to your retention policy
4. Pulls latest Docker images
5. Starts containers back up
6. If the pull fails, automatically restores the previous version

### 2 — Restore from Backup
Lists all available backups (newest first) as a numbered menu and lets you choose one to restore. Stops current containers, clears the current installation, and restores the selected backup.

> ⚠️ **This is a destructive operation.** You must type `YES` (in caps) to confirm.

### 3 — Manage Backups
Lists all available backups with their **disk size** and lets you permanently delete one to free up space.

### 4 — Full Migration (Move to New Disk/Path)
Moves your entire Immich installation to a new location. The process:
1. Stops all containers
2. Exports a full PostgreSQL database dump to the new location as an extra safety net
3. Backs up your `.env` and `docker-compose.yml` with a date-stamped copy
4. Transfers all files using `rsync` (falls back to `cp` if rsync is unavailable)
5. Updates path references in `.env` and the config file automatically
6. Starts Immich from the new location

> ⚠️ **The new disk must be formatted as `ext4`, `xfs`, or `zfs`.** Do **not** use NTFS or exFAT — Docker volumes are not compatible with these filesystems.

### 5 — Emergency Undo (Migration Rollback)
If a migration failed or the terminal closed mid-process, this option detects the backup `.env` file created before the migration and restores it, bringing Immich back online on the original path.

### 6 — Change Settings
Re-runs the Setup Wizard so you can update the Immich path, backup location, or retention policy.

---

## 📁 Backup Naming

Backups are named using the format:

```
immich_backup_YYYYMMDD_HHMMSS
```

For example:
```
immich_backup_20250414_030000
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
- Backups are **full copies** of your Immich directory. Make sure your backup destination has enough free disk space before updating.
- **Before migrating**, verify your new disk is mounted and has sufficient space for your entire photo library.
- **After migrating**, let Immich run for a few days and confirm everything works before deleting data from the old disk.
- **Run as a cron job** to automate regular updates. Example (every Sunday at 3 AM):
  ```bash
  0 3 * * 0 /path/to/immich-management-tool.sh
  ```
  > For unattended cron use, the script would need to be adapted to skip interactive prompts.

---

## ⚠️ Disclaimer

This script modifies and restarts live Docker services and performs destructive operations (deleting directories). Always verify your backup location has sufficient space and test your restore procedure before relying on it in production.

This project is distributed under the **MIT License** — see the [LICENSE](LICENSE) file for full details. In short: this software is provided **"as is"**, without warranty of any kind. The author is **not liable** for any damage, data loss, or issues arising from the use of this script.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for full details.

```
MIT License

Copyright (c) 2025 G.T

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
