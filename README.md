# Hash Organiser

Hash Organiser is a minimal bash tool for processing NTDS dumps during password audits. Converts raw [`secretsdump`](https://github.com/fortra/impacket/blob/master/examples/secretsdump.py) output into structured datasets suitable for cracking and analysis. 

It assumes that the ` -just-dc-ntlm` and `-user-status` flags are used (see [Usage](#usage)).

## Features

- Filters enabled accounts
- Separates machine and user accounts
- Supports optional filtering of test/company accounts
- Extracts deduplicated NTLM hash list
- Detects LM hash presence
- Identifies privileged accounts (via BloodHound JSON)
- Maps privileged accounts to hashes
- Optional: maps cracked hashes back to `username:password` using a Hashcat potfile

## Requirements

The script is based on standard GNU utilities (`grep`, `awk`, `cut`, and `sort`), the only dependency is [`jq`](https://github.com/jqlang/jq).

## Usage

```bash
# Extract NTDS
secretsdump.py puppy.htb/steph.cooper_adm:'Pass123'@10.129.232.75 -user-status -just-dc-ntlm -outputfile puppy.htb

# Extract domain data with a tool of your choice
rusthound-ce -u steph.cooper_adm -p 'Pass123' -d puppy.htb -z

# Unzip files
unzip 20260517110753_puppy-htb_rusthound-ce.zip -d ./bh-data/

# Use hash-organiser
./hash-organiser.sh -i <ntds_file> -b <bh_users_json> [-o output_dir] [-f pattern] [-p potfile]

# Example
./hash-organiser.sh -i puppy.htb.ntds -b ./bh-data/20260517110753_puppy-htb_users.json [-o output_dir] [-f pattern] [-p potfile]
```

The expected output should look like this:

```bash
$ ./hash-organiser.sh -i puppy.htb.ntds.expanded -b bh-data/20260517110753_puppy-htb_users.json -f 'mollysec'
[*] Hash Organiser v1.0 starting...
[+] Output directory: hash-organiser

[*] Analysing account status...
[+] Total accounts: 26
[+] Enabled accounts: 22
    → hash-organiser/ntds-enabled.txt
[+] Disabled accounts: 3
    → hash-organiser/ntds-disabled.txt

[*] Splitting machine and user accounts...
[+] Machine accounts: 2
    → hash-organiser/ntds-machine.txt
[+] User accounts: 20

[*] Applying optional filtering...
[!] Filtered accounts (mollysec): 2
    → hash-organiser/testing-accounts.txt
[+] Clean user dataset
    → hash-organiser/ntds-users-clean.txt

[*] Calculating NTLM hash statistics...
[+] Total NTLM hashes: 18
[+] Unique NTLM hashes: 10

[*] Extracting NTLM hashes...
[+] Deduplicated hash file
    → hash-organiser/ntlm-hashes.txt

[*] Checking for LM hashes...
[!] LM hashes detected: 3
    → hash-organiser/lm-hashes.txt

[*] Extracting privileged accounts (BloodHound)...
[+] Enabled privileged accounts: 2
    → hash-organiser/admin-users.txt

[*] Mapping privileged users to hashes...
[+] Privileged hashes identified: 2
    → hash-organiser/admin-hashes.txt

[✔] Hash Organiser completed successfully
[+] Results stored in: hash-organiser
```
