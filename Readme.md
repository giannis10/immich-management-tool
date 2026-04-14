# 🌟 Immich Management Tool

A Bash script for automated backup, update, and rollback of your [Immich](https://immich.app/) self-hosted installation running via Docker Compose.

**Created by:** G.T

---

## ✨ Features

- 🚀 **Auto-Update** — Stops containers, creates a backup, pulls the latest Docker images, and restarts everything automatically.
- 📦 **Automatic Backup** — Takes a full copy of your Immich directory before every update.
- ⏪ **Rollback / Restore** — Easily roll back to any previous backup if something goes wrong.
- 🗑️ **Backup Management** — View and manually delete old backups.
- 🔍 **Auto-Discovery** — Automatically detects your Immich installation path via Docker labels.
- 🧹 **Backup Rotation** — Automatically removes old backups, keeping only the number you specify.
- ⚙️ **Persistent Config** — Saves your settings to a local config file so you don't have to re-enter them every time.

---

## 📋 Requirements

- Linux system with **Bash**
- **Docker** and **Docker Compose** (v2, using `docker compose`)
- **Root / sudo** privileges
- Immich running as a Docker Compose stack

---

## 🚀 Installation

1. Download or clone the script to your server:

```bash
wget https://raw.githubusercontent.com/giannis10/Immich-Management-Tool/main/immich-management-tool.sh
# or
git clone https://github.com/giannis10/Immich-Management-Tool.git
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
| **Auto-scan** | Optionally scans running Docker containers to find your Immich directory automatically |
| **Manual path** | If auto-scan fails, you can enter the path manually (e.g. `/opt/immich`) |
| **Backup location** | Where backups will be stored (default: `/var/backups/immich`) |
| **Retention policy** | How many old backups to keep before auto-deleting (default: `2`) |

Settings are saved to `immich_update.conf` in the same directory as the script.

---

## 🗂️ Menu Options

```
====================================================
   🌟 IMMICH MANAGEMENT TOOL 🌟
====================================================
1) 🚀 Update Immich (Auto-Backup & Update)
2) ⏪ Restore from Backup (Rollback)
3) 🗑️ Delete a specific Backup
4) ⚙️ Change Settings (Run Setup Again)
5) ❌ Exit
====================================================
```

### 1 — Update Immich
Performs the full update cycle:
1. Stops all Immich containers (`docker compose down`)
2. Creates a timestamped backup of your Immich directory
3. Rotates old backups according to your retention policy
4. Pulls latest Docker images (`docker compose pull`)
5. Starts containers back up (`docker compose up -d`)

### 2 — Restore from Backup
Lists all available backups (newest first) and lets you choose one to restore. Stops current containers, removes the current installation, and restores the selected backup.

> ⚠️ **This is a destructive operation.** You must type `YES` (in caps) to confirm.

### 3 — Delete a Backup
Lists all available backups and lets you permanently delete one manually.

### 4 — Change Settings
Re-runs the Setup Wizard so you can update the Immich path, backup location, or retention policy.

---

## 📁 Backup Naming

Backups are named using the format:

```
immich_backup_DD-MM-YYYY_HH-MM-SS
```

For example:
```
immich_backup_14-04-2025_03-30-00
```

---

## 🔧 Configuration File

The script stores settings in `immich_update.conf` next to the script itself:

```bash
SOURCE_DIR="/opt/immich"
BACKUP_ROOT="/var/backups/immich"
RETAIN_BACKUPS=2
```

You can edit this file manually or use option **4** from the menu.

---

## 💡 Tips

- **Run as a cron job** to automate regular updates. Example (every Sunday at 3 AM):
  ```bash
  0 3 * * 0 /path/to/immich-management-tool.sh
  ```
  > For unattended cron use, you'd need to adapt the script to skip interactive prompts.

- **Keep at least 2 backups** (`RETAIN_BACKUPS=2`) in case the most recent backup itself is corrupted.

- Backups are **full copies** of your Immich directory (using `cp -a`). Make sure your backup destination has enough disk space.

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
