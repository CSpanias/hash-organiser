# Hash Organiser

Hash Organiser is a minimal bash tool for processing NTDS dumps during password audits. It converts raw [`secretsdump`](https://github.com/fortra/impacket/blob/master/examples/secretsdump.py) output into structured datasets suitable for cracking and basic analysis. This was not developed as a production-ready tool, but rather as a simple PoC to accompany the article: [Password Audits Part 2: Hash Organisation](https://mollysec.com/posts/password-audits-part-2/). It assumes that the `-just-dc-ntlm` and `-user-status` flags are used (see [Usage](#usage)).

Vibe-coded with M365 Copilot (GTP-5).

## Features

- Filters enabled accounts
- Separates machine and user accounts
- Extracts deduplicated NTLM hash list
- Detects LM hashes and prepares LM datasets
- Filtering for testing accounts (optional)
- Identifies privileged accounts via BloodHound JSON (optional)
- Maps cracked hashes back to `username:password` format using a Hashcat potfile (optional)

## Requirements

The script is based on standard GNU utilities (`grep`, `awk`, `cut`, and `sort`), the only dependency is [`jq`](https://github.com/jqlang/jq). The latter is only required if using BloodHound data.

## Usage

```bash
# Extract NTDS
secretsdump.py puppy.htb/steph.cooper_adm:'Pass123'@10.129.232.75 -user-status -just-dc-ntlm -outputfile puppy.htb

# Extract domain data and unzip the file (optional)
rusthound-ce -u steph.cooper_adm -p 'Pass123' -d puppy.htb -z && unzip 20260517110753_puppy-htb_rusthound-ce.zip -d ./bh-data/

# Use hash-organiser with just NTDS
./hash-organiser.sh --ntds <ntds-file>

# Use hash-organiser with optional features
./hash-organiser.sh -n <ntds-file> -u <users.json> -f "testing-acc1|testing_acc2" -p <hashcat-potfile> -o <output-directory>
```

Expected output with just NTDS:

```bash
$ ./hash-organiser.sh --ntds puppy.htb.ntds.expanded
[*] Hash Organiser v1.0 starting...
[+] Output directory: hash-organiser

[*] Processing NTDS...
[+] Users retained: 20
[+] NTLM hashes extracted
    → hash-organiser/ntlm-hashes.txt
[!] LM hashes detected
    → hash-organiser/lm-hashes.txt

[✔] Completed
[+] Output: hash-organiser

$ tree hash-organiser/
hash-organiser/
├── lm-hashes.txt
├── lm-users.txt
├── ntds-disabled.txt
├── ntds-enabled.txt
├── ntds-machines.txt
├── ntds-users-clean.txt
└── ntlm-hashes.txt

1 directory, 7 files
```

Expected output with optional features:

```bash
$ ./hash-organiser.sh -n puppy.htb.ntds.expanded -u bh-data/20260517110753_puppy-htb_users.json -f "mollysec" -p test-potfile -o ./test-directory
[*] Hash Organiser v1.0 starting...
[+] Output directory: ./test-directory

[*] Processing NTDS...
[!] Applying filter: mollysec
[+] Users retained: 18
[+] NTLM hashes extracted
    → ./test-directory/ntlm-hashes.txt
[!] LM hashes detected
    → ./test-directory/lm-hashes.txt

[*] Extracting privileged users...
[+] Privileged accounts: 2
    → ./test-directory/admin-users.txt

[*] Mapping cracked hashes...
[+] Cracked credentials: 11
    → ./test-directory/mapped-passwords.txt

[✔] Completed
[+] Output: ./test-directory

$ tree test-directory/
test-directory/
├── admin-hashes.txt
├── admin-users.txt
├── lm-hashes.txt
├── lm-users.txt
├── mapped-passwords.txt
├── ntds-disabled.txt
├── ntds-enabled.txt
├── ntds-machines.txt
├── ntds-users-clean.txt
├── ntlm-hashes.txt
└── testing-accounts.txt

1 directory, 11 files
```
