#!/usr/bin/env bash

###############################################################################
# Hash Organiser v1.0
# Author: Charalampos Spanias (mollysec)
# Date: 17 May 2026
#
# Description:
#   Minimal NTDS post-processing tool for password auditing workflows.
#   Produces clean datasets for cracking, mapping, and analysis.
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

# --- HELP MENU ---
usage() {
    echo "Hash Organiser v$VERSION"
    echo ""
    echo "Usage:"
    echo "  $0 -i <ntds_file> -b <bh_users_json> [-o output_dir] [-f filter_pattern]"
    echo ""
    echo "Options:"
    echo "  -i    NTDS dump file"
    echo "  -b    BloodHound users JSON file"
    echo "  -o    Output directory (default: hash-organiser)"
    echo "  -f    Pattern to filter out (e.g. company/test accounts)"
    echo "  -h    Show this help message"
    echo ""
    exit 1
}

# --- PARSE FLAGS ---
while getopts "i:b:o:f:h" opt; do
    case $opt in
        i) NTDS_FILE="$OPTARG" ;;
        b) BH_JSON="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        f) FILTER_PATTERN="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- VALIDATION ---
if [ -z "$NTDS_FILE" ] || [ -z "$BH_JSON" ]; then
    usage
fi

if [ ! -f "$NTDS_FILE" ]; then
    echo -e "${RED}[!] NTDS file not found${NC}"
    exit 1
fi

if [ ! -f "$BH_JSON" ]; then
    echo -e "${RED}[!] BloodHound JSON file not found${NC}"
    exit 1
fi

# --- DEPENDENCY CHECKS ---
command -v jq >/dev/null 2>&1 || { echo -e "${RED}[!] jq is required but not installed${NC}"; exit 1; }

# --- CREATE OUTPUT DIR ---
mkdir -p "$OUTPUT_DIR"

# --- FILES ---
ENABLED_FILE="$OUTPUT_DIR/ntds-enabled.txt"
DISABLED_FILE="$OUTPUT_DIR/ntds-disabled.txt"
MACHINE_FILE="$OUTPUT_DIR/ntds-machine.txt"
CLEAN_USER_FILE="$OUTPUT_DIR/ntds-users-clean.txt"
FILTERED_FILE="$OUTPUT_DIR/filtered-accounts.txt"
HASH_FILE="$OUTPUT_DIR/ntlm-hashes.txt"
LM_PRESENT_FILE="$OUTPUT_DIR/lm-present.txt"
ADMIN_USERS_FILE="$OUTPUT_DIR/admin-users.txt"
ADMIN_HASHES_FILE="$OUTPUT_DIR/admin-hashes.txt"

echo -e "${BLUE}[*] Hash Organiser v$VERSION starting...${NC}"
echo -e "${GREEN}[+] Output directory:${NC} $OUTPUT_DIR"

# ---------------------------------------------------------------------------
# STEP 1: ACCOUNT STATUS
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Analysing account status...${NC}"

TOTAL_COUNT=$(grep -c ":" "$NTDS_FILE")
ENABLED_COUNT=$(grep -c "(status=Enabled)" "$NTDS_FILE")
DISABLED_COUNT=$(grep -c "(status=Disabled)" "$NTDS_FILE")

echo -e "${GREEN}[+] Total accounts:${NC} $TOTAL_COUNT"
echo -e "${GREEN}[+] Enabled accounts:${NC} $ENABLED_COUNT"
echo -e "    → $ENABLED_FILE"
echo -e "${GREEN}[+] Disabled accounts:${NC} $DISABLED_COUNT"
echo -e "    → $DISABLED_FILE"

grep "(status=Enabled)" "$NTDS_FILE" | awk '{print $1}' > "$ENABLED_FILE"
grep "(status=Disabled)" "$NTDS_FILE" | awk '{print $1}' > "$DISABLED_FILE"

# ---------------------------------------------------------------------------
# STEP 2: SPLIT MACHINE / USER
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Splitting machine and user accounts...${NC}"

awk -F ':' '$1 ~ /\$$/' "$ENABLED_FILE" > "$MACHINE_FILE"
awk -F ':' '$1 !~ /\$$/' "$ENABLED_FILE" > "$CLEAN_USER_FILE.tmp"

COUNT_MACHINES=$(wc -l < "$MACHINE_FILE")
COUNT_USERS=$(wc -l < "$CLEAN_USER_FILE.tmp")

echo -e "${GREEN}[+] Machine accounts:${NC} $COUNT_MACHINES"
echo -e "    → $MACHINE_FILE"
echo -e "${GREEN}[+] User accounts:${NC} $COUNT_USERS"

# ---------------------------------------------------------------------------
# STEP 3: OPTIONAL FILTERING (USER-PROVIDED PATTERN)
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Applying optional filtering...${NC}"

if [ -n "$FILTER_PATTERN" ]; then
    grep -i "$FILTER_PATTERN" "$CLEAN_USER_FILE.tmp" > "$FILTERED_FILE" || true
    grep -vi "$FILTER_PATTERN" "$CLEAN_USER_FILE.tmp" > "$CLEAN_USER_FILE"

    FILTER_COUNT=$(wc -l < "$FILTERED_FILE" || echo 0)

    if [ "$FILTER_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}[!] Filtered accounts (${FILTER_PATTERN}):${NC} $FILTER_COUNT"
        echo -e "    → $FILTERED_FILE"
    fi
else
    mv "$CLEAN_USER_FILE.tmp" "$CLEAN_USER_FILE"
    echo -e "${GREEN}[+] No filtering applied${NC}"
fi

rm -f "$CLEAN_USER_FILE.tmp"

echo -e "${GREEN}[+] Clean user dataset${NC}"
echo -e "    → $CLEAN_USER_FILE"

# ---------------------------------------------------------------------------
# STEP 4: HASH STATISTICS (CLEAN DATASET)
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Calculating NTLM hash statistics...${NC}"

TOTAL_HASHES=$(cut -d ':' -f4 "$CLEAN_USER_FILE" | wc -l)
UNIQUE_HASHES=$(cut -d ':' -f4 "$CLEAN_USER_FILE" | sort -u | wc -l)

echo -e "${GREEN}[+] Total NTLM hashes:${NC} $TOTAL_HASHES"
echo -e "${GREEN}[+] Unique NTLM hashes:${NC} $UNIQUE_HASHES"

# ---------------------------------------------------------------------------
# STEP 5: HASH EXTRACTION
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Extracting NTLM hashes...${NC}"

cut -d ':' -f4 "$CLEAN_USER_FILE" | sort -u > "$HASH_FILE"

echo -e "${GREEN}[+] Deduplicated hash file${NC}"
echo -e "    → $HASH_FILE"

# ---------------------------------------------------------------------------
# STEP 6: LM DETECTION
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Checking for LM hashes...${NC}"

grep -v 'aad3b435b51404eeaad3b435b51404ee' "$CLEAN_USER_FILE" > "$LM_PRESENT_FILE" || true

if [ -s "$LM_PRESENT_FILE" ]; then
    LM_COUNT=$(wc -l < "$LM_PRESENT_FILE")
    echo -e "${RED}[!] LM hashes detected:${NC} $LM_COUNT"
    echo -e "    → $LM_PRESENT_FILE"
else
    rm -f "$LM_PRESENT_FILE"
    echo -e "${GREEN}[+] No LM hashes detected${NC}"
fi

# ---------------------------------------------------------------------------
# STEP 7: BLOODHOUND PRIVILEGED USERS
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Extracting privileged accounts (BloodHound)...${NC}"

jq -r '.data[]
    | select(.Properties.admincount == true and .Properties.enabled == true)
    | .Properties.samaccountname' "$BH_JSON" > "$ADMIN_USERS_FILE"

ADMIN_COUNT=$(wc -l < "$ADMIN_USERS_FILE")

echo -e "${GREEN}[+] Enabled privileged accounts:${NC} $ADMIN_COUNT"
echo -e "    → $ADMIN_USERS_FILE"

# ---------------------------------------------------------------------------
# STEP 8: MAP PRIVILEGED → HASHES
# ---------------------------------------------------------------------------
echo -e "\n${BLUE}[*] Mapping privileged users to hashes...${NC}"

grep -i -f "$ADMIN_USERS_FILE" "$CLEAN_USER_FILE" > "$ADMIN_HASHES_FILE" || true

ADMIN_HASH_COUNT=$(wc -l < "$ADMIN_HASHES_FILE")

echo -e "${GREEN}[+] Privileged hashes identified:${NC} $ADMIN_HASH_COUNT"
echo -e "    → $ADMIN_HASHES_FILE"

# ---------------------------------------------------------------------------
# FINAL
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}[✔] Hash Organiser completed successfully${NC}"
echo -e "${GREEN}[+] Results stored in:${NC} $OUTPUT_DIR"
echo ""
