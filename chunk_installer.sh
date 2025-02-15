#!/bin/bash

# Self-Installation Script for chunk

# Define the target locations
TARGET_BIN="/usr/local/bin/chunk"
LOGFILE="/var/log/chunk.log"
USER=$(whoami)

# Check if running as root (needed for installation)
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Exiting..."
    exit 1
fi

# Define the script content
SCRIPT_CONTENT='#!/bin/bash

# Default settings
CHUNK_SIZE=100      # Default: 100 lines per chunk
TIMEOUT=60          # Default: 60 seconds per chunk
LOGFILE="/var/log/chunk.log"  # Log file location
MAX_RETRIES=3       # Max retries per chunk

# Ensure a command is provided
if [[ -z "$1" ]]; then
    echo "Usage: chunk.sh <command> [chunk_size] [timeout]" >&2
    exit 1
fi

CMD="$1"  # Command to execute on each chunk

# Optionally override chunk_size and timeout if provided
if [[ -n "$2" ]]; then
    CHUNK_SIZE="$2"
fi

if [[ -n "$3" ]]; then
    TIMEOUT="$3"
fi

# Check for write permissions on the log file
if [[ ! -w "$LOGFILE" ]]; then
    sudo touch "$LOGFILE"
    sudo chmod 666 "$LOGFILE"
fi

# Logging function
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | sudo tee -a "$LOGFILE" >/dev/null
    logger -t chunk "$1"  # Send to syslog
}

# Main processing logic with AWK
awk -v n="$CHUNK_SIZE" -v cmd="$CMD" -v log="$LOGFILE" -v timeout="$TIMEOUT" -v retries="$MAX_RETRIES" '
{
    buffer = buffer $0 ORS;
    if (NR % n == 0) {
        process_chunk();
        buffer = "";
    }
}
END {
    if (buffer) {
        process_chunk();
    }
}

function process_chunk() {
    chunk_id = ++chunk_count;
    system("echo \"Processing chunk #" chunk_id "\" | tee -a " log);

    # Attempt up to MAX_RETRIES times
    for (attempt = 1; attempt <= retries; attempt++) {
        cmd_pid = (print buffer | cmd) 2>> log &

        # Wait for completion or kill if it times out
        start_time = systime();
        while (systime() - start_time < timeout) {
            if (system("ps -p " cmd_pid " > /dev/null 2>&1") != 0) {
                return;  # Command finished successfully
            }
            system("sleep 1");
        }

        # Kill process if it exceeded the timeout
        system("kill -9 " cmd_pid " 2>/dev/null");
        system("echo \"Chunk #" chunk_id " timed out, retrying (" attempt "/" retries ")\" | tee -a " log);
    }

    # Final failure log
    system("echo \"Chunk #" chunk_id " failed after " retries " attempts\" | tee -a " log);
}'

wait  # Ensure all backgrounded processes finish

log "All chunks processed."
'

# Copy the script to /usr/local/bin
echo "$SCRIPT_CONTENT" > $TARGET_BIN
chmod +x $TARGET_BIN

# Ensure the log file exists and is writable
if [[ ! -f "$LOGFILE" ]]; then
    touch $LOGFILE
    chmod 666 $LOGFILE
fi

# Create a symlink in /usr/local/bin for easy execution
echo "Creating a symlink in /usr/local/bin..."
ln -sf $TARGET_BIN /usr/local/bin/chunk

# Final message
echo "Installation complete. You can now run 'chunk' from anywhere."

exit 0

