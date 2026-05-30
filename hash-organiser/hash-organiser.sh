#!/usr/bin/env bash

####################################################################################################
# Hash Organiser v1.0                                                                              #  
# Author: Charalampos Spanias (mollysec) & M365 Copilot                                            #
# Date: 17 May 2026                                                                                #
#                                                                                                  #
# Description:                                                                                     #
#   Minimal NTDS post-processing tool for password auditing workflows.                             #
#   Focused on cleaning and preparing datasets for cracking.                                       #
#   Intentionally minimal to serve as a PoC for https://mollysec.com/posts/password-audits-part-2/ #
####################################################################################################

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
BH_USERS=""
POTFILE=""

# --- HELP ---
usage() {
    echo "Hash Organiser v$VERSION"
    echo ""
    echo "Usage:"
    echo "  $0 -n <ntds_file> [options]"
    echo ""
    echo "Options:"
    echo "  -n, --ntds     NTDS dump file (required)"
    echo "  -u, --users    BloodHound users JSON (optional)"
    echo "  -o, --output   Output directory (default: hash-organiser)"
    echo "  -f, --filter   Filter pattern (e.g. 'test|company')"
    echo "  -p, --potfile  Hashcat potfile (optional)"
    echo "  -h, --help     Show this help"
    echo ""
    exit 1
}

# --- PARSE ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--ntds) NTDS_FILE="$2"; shift 2 ;;
        -u|--users) BH_USERS="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -f|--filter) FILTER_PATTERN="$2"; shift 2 ;;
        -p|--potfile) POTFILE="$2"; shift 2 ;;
        -h| --help) usage ;;
        *) usage ;;
    esac
done

# --- VALIDATION ---
[ -z "$NTDS_FILE" ] && usage

if [ ! -f "$NTDS_FILE" ]; then
    echo -e "${RED}[!] NTDS file not found${NC}"
    exit 1
fi

if [ -n "$BH_USERS" ] && [ ! -f "$BH_USERS" ]; then
    echo -e "${RED}[!] users.json not found${NC}"
    exit 1
fi

if [ -n "$POTFILE" ] && [ ! -f "$POTFILE" ]; then
    echo -e "${RED}[!] Potfile not found${NC}"
    exit 1
fi

# jq only if needed
if [ -n "$BH_USERS" ]; then
    command -v jq >/dev/null 2>&1 || {
        echo -e "${RED}[!] jq required for BloodHound parsing${NC}"
        exit 1
    }
fi

# --- PREP ---
mkdir -p "$OUTPUT_DIR"

ENABLED="$OUTPUT_DIR/ntds-enabled.txt"
DISABLED="$OUTPUT_DIR/ntds-disabled.txt"
MACHINES="$OUTPUT_DIR/ntds-machines.txt"
USERS="$OUTPUT_DIR/ntds-users-clean.txt"
FILTERED="$OUTPUT_DIR/testing-accounts.txt"
HASHES="$OUTPUT_DIR/ntlm-hashes.txt"
LM_HASHES="$OUTPUT_DIR/lm-hashes.txt"
LM_USERS="$OUTPUT_DIR/lm-users.txt"
ADMIN_USERS="$OUTPUT_DIR/admin-users.txt"
ADMIN_HASHES="$OUTPUT_DIR/admin-hashes.txt"
MAPPED="$OUTPUT_DIR/mapped-passwords.txt"

echo -e "${BLUE}[*] Hash Organiser v$VERSION starting...${NC}"
echo -e "${GREEN}[+] Output directory:${NC} $OUTPUT_DIR"

# ---------------------------------------------------------------------------
# STEP 1: STATUS
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Processing NTDS...${NC}"

grep "(status=Enabled)" "$NTDS_FILE" | awk '{print $1}' > "$ENABLED"
grep "(status=Disabled)" "$NTDS_FILE" | awk '{print $1}' > "$DISABLED"

# ---------------------------------------------------------------------------
# STEP 2: SPLIT
# ---------------------------------------------------------------------------
awk -F ':' '$1 ~ /\$$/' "$ENABLED" > "$MACHINES"
awk -F ':' '$1 !~ /\$$/' "$ENABLED" > "$USERS.tmp"

# ---------------------------------------------------------------------------
# STEP 3: FILTER
# ---------------------------------------------------------------------------
if [ -n "$FILTER_PATTERN" ]; then
    echo -e "${YELLOW}[!] Applying filter: ${NC}$FILTER_PATTERN"

    grep -i "$FILTER_PATTERN" "$USERS.tmp" > "$FILTERED" || true
    grep -vi "$FILTER_PATTERN" "$USERS.tmp" > "$USERS"

else
    mv "$USERS.tmp" "$USERS"
fi

rm -f "$USERS.tmp"

COUNT_USERS=$(wc -l < "$USERS")
echo -e "${GREEN}[+] Users retained:${NC} $COUNT_USERS"

# ---------------------------------------------------------------------------
# STEP 4: NTLM HASHES
# ---------------------------------------------------------------------------
cut -d ':' -f4 "$USERS" | sort -u > "$HASHES"

echo -e "${GREEN}[+] NTLM hashes extracted${NC}"
echo -e "    → $HASHES"

# ---------------------------------------------------------------------------
# STEP 5: LM HASHES
# ---------------------------------------------------------------------------
grep -v 'aad3b435b51404eeaad3b435b51404ee' "$USERS" > "$LM_USERS" || true

if [ -s "$LM_USERS" ]; then
    cut -d ':' -f3 "$LM_USERS" | sort -u > "$LM_HASHES"
    echo -e "${RED}[!] LM hashes detected${NC}"
    echo -e "    → $LM_HASHES"
else
    rm -f "$LM_USERS"
    echo -e "${GREEN}[+] No LM hashes detected${NC}"
fi

# ---------------------------------------------------------------------------
# STEP 6: PRIVILEGED (optional)
# ---------------------------------------------------------------------------
if [ -n "$BH_USERS" ]; then
    echo -e "\n${BLUE}[*] Extracting privileged users...${NC}"

    jq -r '.data[]
    | select(.Properties.admincount == true and .Properties.enabled == true)
    | .Properties.samaccountname' "$BH_USERS" > "$ADMIN_USERS.tmp"

    if [ -n "$FILTER_PATTERN" ]; then
        grep -vi "$FILTER_PATTERN" "$ADMIN_USERS.tmp" > "$ADMIN_USERS"
    else
        mv "$ADMIN_USERS.tmp" "$ADMIN_USERS"
    fi

    rm -f "$ADMIN_USERS.tmp"

    grep -i -f "$ADMIN_USERS" "$USERS" > "$ADMIN_HASHES" || true

    COUNT_ADMIN=$(wc -l < "$ADMIN_USERS")

    echo -e "${GREEN}[+] Privileged accounts:${NC} $COUNT_ADMIN"
    echo -e "    → $ADMIN_USERS"
fi

# ---------------------------------------------------------------------------
# STEP 7: MAPPING (optional)
# ---------------------------------------------------------------------------
if [ -n "$POTFILE" ]; then
    echo -e "\n${BLUE}[*] Mapping cracked hashes...${NC}"

    awk -F ':' '
    NR==FNR {c[$1]=$2; next}
    ($4 in c) {print $1 ":" c[$4]}
    ' "$POTFILE" "$USERS" > "$MAPPED"

    COUNT_MAPPED=$(wc -l < "$MAPPED")

    echo -e "${GREEN}[+] Cracked credentials:${NC} $COUNT_MAPPED"
    echo -e "    → $MAPPED"
fi

# ---------------------------------------------------------------------------
# FINAL
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}[✔] Completed${NC}"
echo -e "${GREEN}[+] Output:${NC} $OUTPUT_DIR"
