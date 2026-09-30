#!/bin/sh

export SPECIFIC="$1"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

update_needed() {
    # $1 -  file path
    # $2 - remote URL
    
    if [ ! -f "$1" ]; then
        return 0  # Update needed
    fi
    
    remote_date="$( curl --silent --head "$2" 2>/dev/null| grep --ignore-case "last-modified:" | cut --delimiter=' ' --fields=2-)"
    if [ -z "$remote_date" ]; then
        echo "${RED}Failed to get remote file info for $2${NC}" >&2
        return 1
    fi
    
    local_date=$(stat --format='%y' "$1")
    
    # Convert dates to timestamps for comparison
    remote_timestamp="$(date --date="$remote_date" +%s 2>/dev/null)"
    local_timestamp="$( date --date="$local_date"  +%s 2>/dev/null)"
    
    if [ -z "$remote_timestamp" ] || [ -z "$local_timestamp" ]; then
        echo "${YELLOW}Warning: Could not parse file dates, skipping update check${NC}"
	echo "${YELLOW} (remote: $remote_date, local: $local_date)${NC}"
        return 2  # Unable to determine
    fi
    
    if [ $remote_timestamp -gt $local_timestamp ]; then
        echo "${CYAN}Remote file is newer: local=$local_date, remote=$remote_date${NC}"
        return 0
    else	
        echo "${GREEN}Local file is up-to-date (date: $local_date)${NC}"
        return 1
    fi
}

verify_checksum() {
    # $1 - file path
    # $2 - URL to file with checksum
    checksum_type="${3:-sha256}"  # Default to sha256
    
    if [ ! -f "$1" ]; then
        echo "${RED}File not found: $1${NC}" >&2
        return 1
    fi
    
    actual_hash='error'
    if command -v "${checksum_type}sum"  >/dev/null 2>&1; then
        actual_hash=$("${checksum_type}sum" "$1" |  cut  --delimiter=' ' --fields=1)
    else
        echo "${RED}Checksum command not available: ${checksum_type}sum${NC}" >&2
        return 1
    fi
    
    # Download checksum file
    checksum_file=$(mktemp)
    curl --silent "$2" --output "$checksum_file" 2>/dev/null
    if [ ! -s "$checksum_file" ]; then
        echo "${RED}Failed to download checksum from $2${NC}" >&2
        rm "$checksum_file"
        return 1
    fi
    
    if grep --fixed-strings --silent --ignore-case "$actual_hash" "$checksum_file"; then
        echo "${GREEN}✓ Checksum matched for $1${NC}" >&2
        rm "$checksum_file"
        return 0
    else
        echo "${RED}✗ Checksum mismatch for $1${NC}" >&2
        echo "${RED}  Expected: $actual_hash${NC}" >&2
        return 2
    fi
}

get_latest_release() {
    curl --silent "$1" \
	| grep --perl-regexp --only-matching '(?<=href=")[0-9]+(\.[0-9]+)?' \
	| sort -V \
	| tail -n 1
}

get_latest_release_sourceforge () {
    curl --silent "$1" \
        | grep --perl-regexp --only-matching "(?<=net.sf.files = ){.*$" \
        | jq -r 'keys
          | map(select(test("^[0-9]+(\\.[0-9]+)+$")))
          | max_by(split(".") | map(tonumber))'
}


update_url() {
    if [ -z "$RELEASE" ]; then
        echo "${RED}Failed to update release for $NAME${NC}"
	return 1
    fi
    echo "${BLUE}Found $NAME $EDITION release: $RELEASE${NC}"
    if [ "$1" ] || update_needed "$iso_name" "${ISO_DIR}${iso_name}"; then
        echo "${CYAN}Updating $NAME to $RELEASE release...${NC}"
        wget --no-verbose --show-progress -O "$iso_name" "${ISO_DIR}${iso_name}" || return 1
        echo "${GREEN}Updated $NAME to release $RELEASE${NC}"
	if [ "$sig_name" = "skip" ]; then
	    echo "${YELLOW}Skipping checksum check${NC}"
	else
            verify_checksum "$iso_name" "${ISO_DIR}${sig_name}" || return $?
	fi
    fi
    unset NAME BASE_URL EDITION RELEASE ISO_DIR iso_name sig_name
}
