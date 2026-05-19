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
