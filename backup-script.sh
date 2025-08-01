#!/bin/bash


##################
## Hamza Alhalabi
## 24/Jan/2025
##################


# Display the help message
function show_help() {
    echo "Usage: backup-script [DIRECTORY1] [DIRECTORY2] ... [DESTINATION] [RETENTION_DAYS]"
    echo "pass all directories and files that you want to backup, then pass the destination directory "
    echo "at the end pass a number (number of days that backup will be deleted before it) "
    echo "Example:  /home/user/docs /home/user/photos /backup/location 7"
    echo 
    echo "Options:" 
    echo "  --help                 Show this help message and exit" 
    echo "  [DIRECTORY-N]          Specify all directories and files to backup" 
    echo "  [DESTINATION]          Specify the location of the backup" 
    echo "  [RETENTION_DAYS]       Specify the number of retention days" 
}


# Check if --help is provided as the first argument
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# display usage instructions
function usage() {
    echo "Usage: $0 [DIRECTORY1] [DIRECTORY2] ... [DESTINATION] [RETENTION_DAYS]"
    echo "Example: $0 /home/user/docs /home/user/photos /backup/location 7"
    exit 1
}

# check if at least three arguments are provided (directories + destination + retention days)
if [ "$#" -lt 3 ]; then
    echo "Error: At least three arguments: one directory, a destination, and retention days are required"
    # show script usage instructions
    usage
fi


# extract the retention days (last argument)
RETENTION_DAYS="${@: -1}"

# extract the destination (before the last argument)
DESTINATION="${@: -2:1}"

# collect all source directories except the destination and retention days
DIRECTORIES=("${@:1:$#-2}")

BACKUP_DATE=$(date +%Y%m%d)
LOG_FILENAME="backup-$BACKUP_DATE.log"

# Create the backup directory
mkdir -p "$DESTINATION/daily-backups/$BACKUP_DATE"

# Initialize log file
LOG_FILE="$DESTINATION/daily-backups/$BACKUP_DATE/$LOG_FILENAME"
echo "Backup Log - $BACKUP_DATE" > "$LOG_FILE"
echo "Backup started at: $(date)" >> "$LOG_FILE"


# validate that each directory exists
for dir in "${DIRECTORIES[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "Error: Directory '$dir' does not exist" | tee -a "$LOG_FILE" >&2
        exit 2
    fi
done


# Validate that source directories are readable
for dir in "${DIRECTORIES[@]}"; do
    if [ ! -r "$dir" ]; then
        echo "Error: Directory '$dir' is not readable" | tee -a "$LOG_FILE" >&2
        exit 3
    fi
done

# Validate the destination
DEST_DIR=$(dirname "$DESTINATION")
if [ ! -d "$DEST_DIR" ]; then
    echo "Error: Destination directory '$DEST_DIR' does not exist" | tee -a "$LOG_FILE" >&2
    exit 4
fi

# Validate writting permissions
if [ ! -w "$DEST_DIR" ]; then
    echo "Error: No write permissions for the destination directory '$DEST_DIR'" | tee -a "$LOG_FILE" >&2
    exit 5
fi


# Validation for RETENTION_DAYS
if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [ "$RETENTION_DAYS" -lt 1 ] || [ "$RETENTION_DAYS" -gt 365 ]; then
    echo "Error: Retention days must be a positive integer between 1 and 365" | tee -a "$LOG_FILE" >&2
    exit 6
fi



# Validate that there is available disk space 
REQUIRED_SPACE=$(du -s "${DIRECTORIES[@]}" | awk '{total+=$1} END {print total}')
AVAILABLE_SPACE=$(df "$DESTINATION" | awk 'NR==2 {print $4}')
if (( REQUIRED_SPACE > AVAILABLE_SPACE )); then
    echo "Error: Insufficient disk space at destination" | tee -a "$LOG_FILE" >&2
    exit 7
fi


BACKUP_FILENAME="backup-$BACKUP_DATE.tar.gz"

# Add directories to log file
echo "Directories backed up:" >> "$LOG_FILE"
for dir in "${DIRECTORIES[@]}"; do
    echo "- $dir" >> "$LOG_FILE"
done

# Create the tar archive
tar -czf "$DESTINATION/daily-backups/$BACKUP_DATE/$BACKUP_FILENAME" "${DIRECTORIES[@]}" 2>>"$LOG_FILE"

# Check if the tar command was successful
if [ $? -eq 0 ]; then
    # Get the size of the backup file
    BACKUP_SIZE=$(du -h "$DESTINATION/daily-backups/$BACKUP_DATE/$BACKUP_FILENAME" | cut -f1)
    echo "Backup successful! Archive created at '$DESTINATION/daily-backups/$BACKUP_DATE/$BACKUP_FILENAME'" >> "$LOG_FILE"
    echo "Backup file size: $BACKUP_SIZE" >> "$LOG_FILE"
else
    echo "Error: Failed to create the backup" >> "$LOG_FILE"
    exit 8
fi

# Delete files older than the retention period
echo "Cleaning up old backups..." >> "$LOG_FILE"
DELETED_FILES=$(find "$DESTINATION/daily-backups/"* -mtime +$RETENTION_DAYS -print -delete)
if [ -n "$DELETED_FILES" ]; then
        echo "Deleted backup files older than $RETENTION_DAYS days:" >> "$LOG_FILE"
    echo "$DELETED_FILES" >> "$LOG_FILE"
else
        echo "No backup files older than $RETENTION_DAYS days to delete" >> "$LOG_FILE"
fi

# Finalize log
echo "Backup completed at: $(date)" >> "$LOG_FILE"
echo "Backup process finished" >> "$LOG_FILE"

# Print log to the console
cat "$LOG_FILE"
