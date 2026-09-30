#!/usr/bin/env bash

MIRROR_URL="https://mirror.hostiko.network"

update_needed() {
    local file_path="$1"
    local remote_url="$2"
    
    # If file doesn't exist, update is needed
    if [[ ! -f "$file_path" ]]; then
        return 0
    fi
    
    local remote_info=$(curl -sI "$remote_url" 2>/dev/null)
    if [[ -z "$remote_info" ]]; then
        echo "Failed to get remote file info for $remote_url" >&2
        return 2
    fi
    
    local remote_date=$(echo "$remote_info" | grep -i "last-modified:" | cut -d' ' -f2-)/
    local local_date=$(stat -c%y "$file_path" 2>/dev/null | cut -d. -f1)
    
    # Convert dates to timestamps for comparison
    local remote_timestamp=$(date -d "$remote_date" +%s 2>/dev/null)
    local local_timestamp=$(date -d "$local_date" +%s 2>/dev/null)
    
    if [[ -z "$remote_timestamp" ]] || [[ -z "$local_timestamp" ]]; then
        echo -n "Warning: Could not parse file dates, skipping update check"
	echo " (remote: $remote_date, local: $local_date)"
        return 2 
    fi
    
    # If remote is newer, update is needed
    if [[ $remote_timestamp -gt $local_timestamp ]]; then
        echo "Remote file is newer: local=$local_date, remote=$remote_date"
        return 0
    fi
    
    echo "Local file is up-to-date (date: $local_date)"
    return 1
}

verify_checksum() {
    local file_path="$1"
    local checksum_url="$2"
    local checksum_type="${3:-sha256}"  # Default to sha256
    
    if [[ ! -f "$file_path" ]]; then
        echo "File not found: $file_path" >&2
        return 1
    fi
    
    # Download checksum file
    local checksum_file=$(mktemp)
    curl -sS "$checksum_url" -o "$checksum_file" 2>/dev/null
    if [[ ! -f "$checksum_file" ]]; then
        echo "Failed to download checksum from $checksum_url" >&2
        rm -f "$checksum_file"
        return 1
    fi
    
    # Extract the hash for the current file
    local filename=$(basename "$file_path")
    local expected_hash=$(grep "$filename" "$checksum_file" | awk '{print $1}')
    
    if [[ -z "$expected_hash" ]]; then
	#TODO: add handling for .sig files
        echo "Could not find checksum for $filename in $checksum_url" >&2
        rm -f "$checksum_file"
        return 1
    fi
    
    # Calculate local checksum
    local actual_hash
    if command -v "${checksum_type}sum" &> /dev/null; then
        actual_hash=$("${checksum_type}sum" "$file_path" | awk '{print $1}')
    else
        echo "Checksum command not available: ${checksum_type}sum" >&2
        rm -f "$checksum_file"
        return 1
    fi
    
    # Compare checksums
    if [[ "$expected_hash" == "$actual_hash" ]]; then
        echo "✓ Checksum verified for $filename"
        rm -f "$checksum_file"
        return 0
    else
        echo "✗ Checksum mismatch for $filename" >&2
        echo "  Expected: $expected_hash" >&2
        echo "  Got:      $actual_hash" >&2
        rm -f "$checksum_file"
        return 1
    fi
}

get_latest_release() {
    local version=$(curl -s "$1" \
	| grep -Po '(?<=href=")[0-9]+(\.[0-9]+)?' \
	| sort -V \
	| tail -n 1)
    if [[ -z "$version" ]]; then
        echo "Failed to detect latest version. from $1" >&2
        exit 1
    fi
    echo "$version"
}

update_distro() {
    echo "Latest $NAME release: $RELEASE"
    if update_needed "$iso_name" "${ISO_DIR}${iso_name}"; then
        echo "Updating $NAME to release $RELEASE..."
        wget -O "$iso_name" "${ISO_DIR}${iso_name}"
        echo "Updated $NAME to release $RELEASE"
        verify_checksum "$iso_name" "${ISO_DIR}${sig_name}" "sha256"
    else
        echo "$NAME is already up-to-date, skipping download"
    fi
    unset NAME BASE_URL EDITION RELEASE ISO_DIR iso_name sig_name
}

# Update Mint
# https://mirror.hostiko.network/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso
NAME="Linux Mint"
BASE_URL="${MIRROR_URL}/linuxmint/stable/"
EDITION="cinnamon"
RELEASE="$(get_latest_release "$BASE_URL")"
ISO_DIR="${BASE_URL}${RELEASE}/"
iso_name="linuxmint-${RELEASE}-${EDITION}-64bit.iso"
sig_name="linuxmint-${RELEASE}-${EDITION}-64bit.sig"
update_distro

# Update Arch
NAME="Arch Linux"
BASE_URL="${MIRROR_URL}/archlinux/iso/"
EDITION="latest"
RELEASE=""
ISO_DIR="${BASE_URL}${EDITION}/"
iso_name="archlinux-x86_64.iso"
sig_name="archlinux-x86_64.iso.sig"
update_distro

# Update Fedora
# hostiko no longer hosts fedora :/
# https://mirror.hostiko.network/fedora/linux/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso  - whyyyyy "-Desktop"??!?
# https://mirror.hostiko.network/fedora/linux/releases/43/Workstation/x86_64/iso/Fedora-Workstation-Live-43-1.6.x86_64.iso
#NAME="Fedora"
#BASE_URL="${MIRROR_URL}/fedora/linux/releases/"
#EDITION="KDE"
#RELEASE=$(get_latest_release "${BASE_URL}")
#ISO_DIR="${BASE_URL}${RELEASE}/${EDITION}/x86_64/iso/"
#iso_name=$(curl -s "$ISO_DIR" \
#    | grep -Po "(?<=href=\")Fedora-${EDITION}-.+-${RELEASE}-.+.iso(?=\" )" )
#sig_name=$(curl -s "$ISO_DIR" \
#    |  grep -Po "(?<=href=\")Fedora-${EDITION}-.+CHECKSUM(?=\" )" )
#update_distro

# Update Ubuntu
# https://mirror.hostiko.network/ubuntu-releases/26.04/ubuntu-26.04-desktop-amd64.iso
NAME="Ubuntu"
BASE_URL="${MIRROR_URL}/ubuntu-releases/"
EDITION="desktop-amd64"
RELEASE="$(get_latest_release "$BASE_URL")"
ISO_DIR="${BASE_URL}${RELEASE}/"
iso_name="ubuntu-${RELEASE}-${EDITION}.iso"
sig_name="SHA256SUMS"
update_distro
