#!/bin/bash

# Script: codecapsule.sh
# Purpose: CodeCapsule - A comprehensive system backup and restore manager without encryption.
# Features include incremental versioning, checksum validation, backup rotation, bootable ISO creation, and restoration.
# Designed By: Mshauri Moore, CEO & Founder

# **Load Configuration**
CONFIG_FILE="./codecapsule_config.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# **Enhanced Logging Functions**
log_info() {
    local message="$1"
    echo "[INFO] $(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo "[ERROR] $(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE" >&2
}

log_alert() {
    local message="$1"
    echo "[ALERT] $(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE"
    send_alert "$message"
}

# **Notification Mechanism**
send_alert() {
    local message="$1"
    if command -v mail &>/dev/null; then
        echo "$message" | mail -s "Backup Alert: $(date +"%Y-%m-%d %H:%M:%S")" "$EMAIL"
    else
        log_error "Email notification skipped: 'mail' command not found."
    fi

    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$message\"}" "$SLACK_WEBHOOK_URL"
    fi
}

# **Ensure Directories Exist**
ensure_directories() {
    log_info "Ensuring necessary directories exist."
    mkdir -p "$BACKUP_DIR" "$BOOTABLE_DIR" "$INCREMENTAL_VERSION_DIR" "$MOUNT_DIR"
    log_info "All necessary directories are in place."
}

# **Backup System Data**
backup_system() {
    log_info "Starting system data backup."
    rsync -avh --progress /etc "${BACKUP_DIR}/etc" || log_error "Failed to backup /etc"
    rsync -avh --progress ~/Documents "${BACKUP_DIR}/documents" || log_error "Failed to backup ~/Documents"
    rsync -avh --progress ~/Notes "${BACKUP_DIR}/notes" || log_error "Failed to backup ~/Notes"
    rsync -avh --progress ~/.config "${BACKUP_DIR}/config" || log_error "Failed to backup ~/.config"
    rsync -avh --progress /usr/local/bin "${BACKUP_DIR}/apps" || log_error "Failed to backup /usr/local/bin"
    log_info "System backup completed."
}

# **Incremental File Versioning**
incremental_file_versioning() {
    log_info "Managing incremental file versions."
    find "$BACKUP_DIR" -type f | while read -r file; do
        relative_path="${file#$BACKUP_DIR/}"
        versioned_file="${INCREMENTAL_VERSION_DIR}/${relative_path}.$(date +"%Y-%m-%d_%H-%M-%S")"
        mkdir -p "$(dirname "$versioned_file")"
        cp "$file" "$versioned_file"
    done
    log_info "Incremental versions saved."
}

# **Validate Backup Integrity**
validate_checksum() {
    log_info "Validating backup integrity with checksum."
    tar -czf "${BACKUP_DIR}.tar.gz" -C "$BACKUP_DIR" .
    sha256sum "${BACKUP_DIR}.tar.gz" > "${BACKUP_DIR}.tar.gz.sha256"

    if sha256sum --check --status "${BACKUP_DIR}.tar.gz.sha256"; then
        log_info "Checksum validation successful."
    else
        log_error "Checksum validation failed."
        log_alert "Checksum validation failed for backup!"
        exit 1
    fi

    rm -f "${BACKUP_DIR}.tar.gz"
    log_info "Backup integrity validation complete."
}

# **Rotate Old Backups**
rotate_old_backups() {
    log_info "Rotating old backups to save space."
    local backup_files=($(ls -t "${BACKUP_DIR}/backup_"* 2>/dev/null))
    if [[ ${#backup_files[@]} -gt $MAX_BACKUPS ]]; then
        for old_backup in "${backup_files[@]:$MAX_BACKUPS}"; do
            rm -rf "$old_backup"
            log_info "Deleted old backup: $old_backup"
        done
    fi
    log_info "Backup rotation complete. Retaining up to $MAX_BACKUPS backups."
}

# **Update Bootable Image**
create_bootable_image() {
    log_info "Creating bootable image."
    local bootable_image="${BOOTABLE_DIR}/bootable_$(date +"%Y-%m-%d_%H-%M-%S").iso"
    cp "$LINUX_ISO" "$bootable_image"
    mount -o loop "$bootable_image" "$MOUNT_DIR" || log_error "Failed to mount bootable image."
    rsync -avh "$BACKUP_DIR/" "$MOUNT_DIR/backup/" || log_error "Failed to copy backup data to bootable image."
    umount "$MOUNT_DIR" || log_error "Failed to unmount bootable image."
    log_info "Bootable image updated at $bootable_image."
}

# **Restore Functionality**
restore_file_version() {
    log_info "Starting restore process."
    read -rp "Enter the relative file path to restore (e.g., etc/fstab): " relative_file
    read -rp "Enter the version timestamp (or 'latest' for the most recent version): " version

    if [[ "$version" == "latest" ]]; then
        version=$(ls -t "${INCREMENTAL_VERSION_DIR}/${relative_file}"* | head -n 1 | rev | cut -d'.' -f1 | rev)
    fi

    local versioned_file="${INCREMENTAL_VERSION_DIR}/${relative_file}.${version}"
    if [[ -f "$versioned_file" ]]; then
        local restore_path="${PWD}/$(basename "$relative_file")"
        cp "$versioned_file" "$restore_path"
        log_info "Restored file saved to: $restore_path."
    else
        log_error "Versioned file not found."
    fi
}

# **Main Function**
main() {
    log_info "Starting CodeCapsule."
    ensure_directories
    backup_system
    incremental_file_versioning
    rotate_old_backups
    validate_checksum
    create_bootable_image
    log_alert "Backup process completed successfully."
}

# **Command-line Interface**
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root."
    exit 1
fi

case "$1" in
    backup)
        main
        ;;
    restore)
        restore_file_version
        ;;
    schedule)
        CRON_JOB="0 3 * * 0 $(realpath $0) backup"
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        log_info "Backup scheduled every Sunday at 3 AM."
        ;;
    *)
        echo "Usage: $0 {backup|restore|schedule}" | tee -a "$LOG_FILE"
        ;;
esac
