#!/bin/sh

SPECIFIC="$1"

update_needed() {
    local file_path="$1"
    local remote_url="$2"
    
    # If file doesn't exist, update is needed
    if [ ! -f "$file_path" ]; then
        return 0  # Update needed
    fi
    
    local remote_info=$(curl -sI "$remote_url" 2>/dev/null)
    if [ -z "$remote_info" ]; then
        echo "Failed to get remote file info for $remote_url" >&2
        return 1
    fi
    
    local remote_date=$(echo "$remote_info" | grep -i "last-modified:" | cut -d' ' -f2-)
    local local_date=$(stat -c%y "$file_path")
    
    # Convert dates to timestamps for comparison
    local remote_timestamp=$(date -d "$remote_date" +%s 2>/dev/null)
    local local_timestamp=$(date -d "$local_date" +%s 2>/dev/null)
    
    if [ -z "$remote_timestamp" -o -z "$local_timestamp" ]; then
        echo -n "Warning: Could not parse file dates, skipping update check"
	echo " (remote: $remote_date, local: $local_date)"
        return 2  # Unable to determine
    fi
    
    if [ $remote_timestamp -gt $local_timestamp ]; then
        echo "Remote file is newer: local=$local_date, remote=$remote_date"
        return 0
    else	
        echo "Local file is up-to-date (date: $local_date)"
        return 1
    fi
}

verify_checksum() {
    local file_path="$1"
    local checksum_url="$2"
    local checksum_type="${3:-sha256}"  # Default to sha256
    
    if [[ ! -f "$file_path" ]]; then
        echo "File not found: $file_path" >&2
        return 1
    fi
    
    local actual_hash
    if command -v "${checksum_type}sum" &> /dev/null; then
        actual_hash=$("${checksum_type}sum" "$file_path" |  cut -d' ' -f1)
    else
        echo "Checksum command not available: ${checksum_type}sum" >&2
        return 1
    fi
    
    # Download checksum file
    local checksum_file=$(mktemp)
    curl -sS "$checksum_url" -o "$checksum_file" 2>/dev/null
    if [ ! -s "$checksum_file" ]; then
        echo "Failed to download checksum from $checksum_url" >&2
        rm "$checksum_file"
        return 1
    fi
    
    if grep -Fqi "$actual_hash" "$checksum_file"; then
        echo "✓ Checksum matched for $file_path" >&2
        rm "$checksum_file"
        return 0
    else
        echo "✗ Checksum mismatch for $file_path" >&2
        echo "  Expected: $actual_hash" >&2
        echo "$checksum_file"
        return 2
    fi
}

get_latest_release() {
    curl --silent "$1" \
	| grep -Po '(?<=href=")[0-9]+(\.[0-9]+)?' \
	| sort -V \
	| tail -n 1
}

get_latest_release_sourceforge () {
    curl --silent "$1" \
        | grep -Po "(?<=net.sf.files = ){.*$" \
        | jq -r 'keys
          | map(select(test("^[0-9]+(\\.[0-9]+)+$")))
          | max_by(split(".") | map(tonumber))'
}


update_url() {
    if [ -z "$RELEASE" ]; then
        echo "Failed to update release for $NAME"
	return 1
    fi
    echo "$NAME release: $RELEASE"
    if [ $1 ] || update_needed "$iso_name" "${ISO_DIR}${iso_name}"; then
        echo "Updating $NAME to $RELEASE release..."
        wget --no-verbose --show-progress -O "$iso_name" "${ISO_DIR}${iso_name}" || return 1
        #wget --verbose --show-progress -O "$iso_name" "${ISO_DIR}${iso_name}"
        echo "Updated $NAME to release $RELEASE"
	if [ "$sig_name" = "skip" ]; then
	    echo "Skipping checksum check"
	else
            verify_checksum "$iso_name" "${ISO_DIR}${sig_name}"
	fi
    fi
    unset NAME BASE_URL EDITION RELEASE ISO_DIR iso_name sig_name
}
