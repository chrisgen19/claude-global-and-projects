---
name: wp-backup
description: Backs up a WordPress site by exporting the database as SQL and zipping the WordPress files. Use when the user says "backup", "back up", "export", or needs to migrate/archive a WordPress site.
---
When performing a WordPress backup, follow these steps:

## 1. Locate WordPress Root
- Starting from the current directory, traverse UP the directory tree to find `wp-config.php`
  ```bash
  # Search upward from current directory
  DIR=$(pwd)
  while [ "$DIR" != "/" ]; do
    if [ -f "$DIR/wp-config.php" ]; then
      echo "Found WordPress root: $DIR"
      break
    fi
    DIR=$(dirname "$DIR")
  done
  ```
- This ensures the command works even if run from inside:
  - `wp-content/themes/my-theme/`
  - `wp-content/plugins/my-plugin/`
  - `wp-content/`
  - Or any nested subdirectory
- If `wp-config.php` is not found after reaching `/`, ask the user for the WordPress root path manually
- Store the WordPress root path as `WP_ROOT` and use it throughout the backup process

## 2. Identify WordPress Configuration
- Extract database credentials from `$WP_ROOT/wp-config.php`:
  - `DB_NAME`
  - `DB_USER`
  - `DB_PASSWORD`
  - `DB_HOST`
  - `DB_CHARSET`
  - Table prefix (`$table_prefix`)

## 3. Create Backup Directory
- Create a timestamped backup folder inside the WordPress root: `$WP_ROOT/backups/backup_YYYY-MM-DD_HH-MM-SS/`
- If a `backups/` folder doesn't exist, create one

## 4. Database Backup
- Use `mysqldump` to export the database:
  ```bash
  mysqldump -u [DB_USER] -p'[DB_PASSWORD]' -h [DB_HOST] --single-transaction --routines --triggers [DB_NAME] > $WP_ROOT/backups/backup_YYYY-MM-DD_HH-MM-SS/database.sql
  ```
- If `mysqldump` is not available, check for `wp-cli` and use:
  ```bash
  wp db export $WP_ROOT/backups/backup_YYYY-MM-DD_HH-MM-SS/database.sql --path=$WP_ROOT
  ```
- Verify the SQL file is not empty after export
- Report the file size of the SQL dump

## 5. File Backup
- Zip the WordPress directory, excluding unnecessary files:
  ```bash
  zip -r $WP_ROOT/backups/backup_YYYY-MM-DD_HH-MM-SS/files.zip $WP_ROOT \
    -x "*/node_modules/*" \
    -x "*/backups/*" \
    -x "*/.git/*" \
    -x "*/wp-content/cache/*" \
    -x "*/wp-content/debug.log" \
    -x "*/wp-content/updraft/*" \
    -x "*/wp-content/upgrade/*"
  ```
- If the user only wants specific folders (e.g., theme or plugin only), ask and zip only those
- Report the file size of the zip

## 6. Optional: Zip Everything Together
- Ask the user if they want a single combined archive:
  ```bash
  zip -r $WP_ROOT/backups/backup_YYYY-MM-DD_HH-MM-SS.zip $WP_ROOT/backups/backup_YYYY-MM-DD_HH-MM-SS/
  ```

## 7. Summary
After backup completes, provide a summary:
- WordPress root path detected
- Current working directory (so user knows where the command was run from)
- Backup location and total size
- Database name and SQL file size
- Files zip size
- Number of tables exported
- Any warnings or errors encountered
- Remind the user to store the backup in a safe location (external drive, cloud storage, etc.)

## Important Notes
- Never display database passwords in output — mask them
- If the database is large (>500MB), warn the user it may take a while
- If running on a live server, prefer `--single-transaction` to avoid locking tables
- If credentials are wrong or connection fails, show a clear error and ask the user to verify `wp-config.php`
- Always resolve the WordPress root FIRST before doing anything else