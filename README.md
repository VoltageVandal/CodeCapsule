# CodeCapsule

CodeCapsule is a comprehensive backup manager designed for simplicity, reliability, and functionality. It automates system backups, incremental versioning, checksum validation, backup rotation, and bootable ISO creation. Restore functionality is also included.

## Features

- **Backup Automation**: Easily back up system files, documents, configurations, and applications.
- **Incremental Versioning**: Save historical versions of files for efficient restoration.
- **Checksum Validation**: Ensures the integrity of backups using SHA256.
- **Backup Rotation**: Automatically manages and deletes old backups to save space.
- **Bootable ISO Creation**: Generate bootable images containing the latest backups.
- **Restore Capability**: Restore specific files or versions from incremental backups.
- **Notifications**: Get alerts via email and Slack.

## Usage

1. **Backup**:
   ```bash
   sudo ./codecapsule.sh backup
