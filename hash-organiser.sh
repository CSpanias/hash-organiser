#!/usr/bin/env bash

###############################################################################
# Hash Organiser v1.0
# Author: Charalampos Spanias (mollysec)
# Date: 17 May 2026
###############################################################################

set -e

VERSION="1.0"

# --- COLOURS ---
BLUE="\033[1;34m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

# --- DEFAULTS ---
OUTPUT_DIR="hash-organiser"
FILTER_PATTERN=""
POTFILE=""

# --- HELP ---
usage() {
    echo "Hash Organiser v$VERSION"
    echo ""
    echo "Usage:"
    echo "  $0 -i <ntds_file> -b <bh_users_json> -g <bh_groups_json> [-o dir] [-f pattern] [-p potfile]"
    echo ""
    echo "Options:"
    echo "  -i NTDS dump file"
    echo "  -b BloodHound users.json"
    echo "  -g BloodHound groups.json"
    echo "  -o Output directory"
    echo "  -f Filter pattern (test/company accounts)"
    echo "  -p Hashcat potfile"
    echo ""
    exit 1
}

# --- PARSE ---
while getopts "i:b:g:o:f:p:h" opt; do
    case $opt in
        i) NTDS_FILE="$OPTARG" ;;
        b) BH_USERS="$OPTARG" ;;
        g) BH_GROUPS="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        f) FILTER_PATTERN="$OPTARG" ;;
        p) POTFILE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- VALIDATION ---
[ -z "$NTDS_FILE" ] && usage
[ -z "$BH_USERS" ] && usage
[ -z "$BH_GROUPS" ] && usage

[ ! -f "$NTDS_FILE" ] && echo "[!] NTDS missing" && exit 1
[ ! -f "$BH_USERS" ] && echo "[!] users.json missing" && exit 1
[ ! -f "$BH_GROUPS" ] && echo "[!] groups.json missing" && exit 1
[ -n "$POTFILE" ] && [ ! -f "$POTFILE" ] && echo "[!] potfile missing" && exit 1

command -v jq >/dev/null || { echo "[!] jq required"; exit 1; }

mkdir -p "$OUTPUT_DIR"

# --- FILES ---
ENABLED="$OUTPUT_DIR/ntds-enabled.txt"
DISABLED="$OUTPUT_DIR/ntds-disabled.txt"
MACHINE="$OUTPUT_DIR/ntds-machine.txt"
USERS="$OUTPUT_DIR/ntds-users-clean.txt"
FILTERED="$OUTPUT_DIR/testing-accounts.txt"
HASHES="$OUTPUT_DIR/ntlm-hashes.txt"
LM="$OUTPUT_DIR/lm-hashes.txt"
USERNAMES="$OUTPUT_DIR/usernames.txt"
ADMINS="$OUTPUT_DIR/admin-users.txt"
ADMIN_HASHES="$OUTPUT_DIR/admin-hashes.txt"
DA_USERS="$OUTPUT_DIR/domain-admins.txt"
DA_HASHES="$OUTPUT_DIR/domain-admin-hashes.txt"
MAPPED="$OUTPUT_DIR/mapped-passwords.txt"

echo "[*] Starting Hash Organiser"

# ---------------------------------------------------------------------------
# STEP 1: ENABLED/DISABLED
# ---------------------------------------------------------------------------
grep "(status=Enabled)" "$NTDS_FILE" | awk '{print $1}' > "$ENABLED"
grep "(status=Disabled)" "$NTDS_FILE" | awk '{print $1}' > "$DISABLED"

# ---------------------------------------------------------------------------
# STEP 2: SPLIT
# ---------------------------------------------------------------------------
awk -F: '$1 ~ /\$$/' "$ENABLED" > "$MACHINE"
awk -F: '$1 !~ /\$$/' "$ENABLED" > "$USERS.tmp"

# ---------------------------------------------------------------------------
# STEP 3: FILTER
# ---------------------------------------------------------------------------
if [ -n "$FILTER_PATTERN" ]; then
    grep -i "$FILTER_PATTERN" "$USERS.tmp" > "$FILTERED" || true
    grep -vi "$FILTER_PATTERN" "$USERS.tmp" > "$USERS"
else
    mv "$USERS.tmp" "$USERS"
fi
rm -f "$USERS.tmp"

# ---------------------------------------------------------------------------
# STEP 4: USERNAMES
# ---------------------------------------------------------------------------
cut -d: -f1 "$USERS" > "$USERNAMES"

# ---------------------------------------------------------------------------
# STEP 5: HASHES
# ---------------------------------------------------------------------------
cut -d: -f4 "$USERS" | sort -u > "$HASHES"

# ---------------------------------------------------------------------------
# STEP 6: LM DETECTION
# ---------------------------------------------------------------------------
grep -v 'aad3b435b51404eeaad3b435b51404ee' "$USERS" > "$LM" || true
[ ! -s "$LM" ] && rm -f "$LM"

# ---------------------------------------------------------------------------
# STEP 7: PRIVILEGED USERS (adminCount)
# ---------------------------------------------------------------------------
jq -r '.data[] | select(.Properties.admincount==true and .Properties.enabled==true) | .Properties.samaccountname' "$BH_USERS" > "$ADMINS.tmp"

if [ -n "$FILTER_PATTERN" ]; then
    grep -vi "$FILTER_PATTERN" "$ADMINS.tmp" > "$ADMINS"
else
    mv "$ADMINS.tmp" "$ADMINS"
fi
rm -f "$ADMINS.tmp"

# map privileged hashes
grep -i -f "$ADMINS" "$USERS" > "$ADMIN_HASHES" || true

# ---------------------------------------------------------------------------
# STEP 8: DOMAIN ADMINS (RID 512 via groups.json)
# ---------------------------------------------------------------------------
jq -r '.data[] | select(.ObjectIdentifier | endswith("-512")) | .Members[]?.ObjectIdentifier' "$BH_GROUPS" |
jq -R -s 'split("\n")[:-1]' |
jq -r --slurpfile sids /dev/stdin '.data[] | select(.ObjectIdentifier as $sid | $sids[0] | index($sid)) | .Properties.samaccountname' "$BH_USERS" |
{ [ -n "$FILTER_PATTERN" ] && grep -vi "$FILTER_PATTERN" || cat; } > "$DA_USERS"

# map DA hashes
grep -i -f "$DA_USERS" "$USERS" > "$DA_HASHES" || true

# ---------------------------------------------------------------------------
# STEP 9: POTFILE MAPPING
# ---------------------------------------------------------------------------
if [ -n "$POTFILE" ]; then
    awk -F: 'NR==FNR{c[$1]=$2;next} ($4 in c){print $1 ":" c[$4]}' "$POTFILE" "$USERS" > "$MAPPED"
fi

# ---------------------------------------------------------------------------
# DONE
# ---------------------------------------------------------------------------
echo "[+] Done"
echo "[+] Output: $OUTPUT_DIR"
