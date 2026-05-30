# Phase Cracker

Phase Cracker is a minimal Python tool for structuring password cracking into defined phases during password audits. It allows you to execute sequential attacks using Hashcat while producing minimal metrics. This was not developed as a production-ready tool, but rather as a simple PoC to accompany the article: [Password Audits Part 3: Cracking Hashes](https://mollysec.com/posts/password-audits-part-3/).

Vibe-coded with M365 Copilot (GPT-5).

---

## Features

- Structured multi-phase cracking (wordlists + optional rulesets)
- Clear separation of attack stages
- Tracks new vs total recovered hashes per phase
- Human-readable execution time (hh:mm:ss:ms)
- Benchmark-based time estimation (--estimate)
- Cached keyspace calculation for fast repeated runs
- Markdown report of results (--report)

---

## Requirements

- Hashcat
- Python 3.10+
- Wordlists and rulesets accessible locally

---

## Usage

### Configuration

Everything must be first configured in the `config.json` file. An example configuration can be found below:

```json
{
  "parameters": {
    "sessionName": "PoC-session",
    "hashDataset": "ntlm-hashes.txt",
    "hashMode": "1000",
    "flags": ["-O", "-w", "4", "-d", "1,3", "--potfile-path", ".\\poc-session.potfile"]
  },

  "phases": [
    {
      "wordlist": "rockyou.txt",
            "Password Strength":"Extremely weak"
    },
    {
      "wordlist": "rockyou.txt",
      "rule": "OneRuleToRuleThemStill.rule",
            "Password Strength":"Weak"
    },
    {
      "wordlist": "weakpass_4a.txt",
      "rule": "best66.rule",
            "Password Strength":"Medium"
    }
  ]
}
```

### Estimate (no execution)

The `--estimate` flag calculates the benchmark speed and then the effective speed based on an arbitrary number (benchmark speed divided by five). The number five was used solely based on the article's numbers as a PoC, therefore, **expect the `Est. Time` column to be wildly off**. 

```powershell
> python .\hashcat-phase-runner.py --config .\config.json --estimate
[*] Running benchmark...
[*] Raw benchmark speed: 38883.5 MH/s
[*] Using effective speed: benchmark / 5

# Phase Estimation

| Phase | Wordlist        | Ruleset                     | Keyspace        | Est. Time    |
|-------|-----------------|-----------------------------|-----------------|--------------|
| 1     | rockyou.txt     | None                        | 14,344,392      | 1ms          |
| 2     | rockyou.txt     | OneRuleToRuleThemStill.rule | 694,828,004,088 | 1m 29s 347ms |
| 3     | weakpass_4a.txt | best66.rule                 | 759,260,159,370 | 1m 37s 632ms |
```

### Cracking

Running the script without the `--estimate` flag, will run the configured phases:

```powershell
> python .\hashcat-phase-runner.py --config .\config.json --report

========================================
[+] Starting phased hashcat run
Session : PoC-session
Hashes  : ntlm-hashes.txt
Mode    : 1000
========================================

----------------------------------------
[+] Phase 1
Wordlist : rockyou.txt
Ruleset  : None
----------------------------------------
[+] Phase 1 running...

[+] Phase 1 completed
Started        : Sat May 30 16:23:27 2026
Duration       : 3s 218ms
Recovered      : 3
Total Recovered: 3

----------------------------------------
[+] Phase 2
Wordlist : rockyou.txt
Ruleset  : OneRuleToRuleThemStill.rule
----------------------------------------
[+] Phase 2 running...

[+] Phase 2 completed
Started        : Sat May 30 16:23:31 2026
Duration       : 1m 54s 798ms
Recovered      : 1
Total Recovered: 4

----------------------------------------
[+] Phase 3
Wordlist : weakpass_4a.txt
Ruleset  : best66.rule
----------------------------------------
[+] Phase 3 running...

[+] Phase 3 completed
Started        : Sat May 30 16:25:25 2026
Duration       : 9m 39s 616ms
Recovered      : 0
Total Recovered: 4

[+] All phases completed


# Phase Report

| Phase | Duration     | Recovered (New/Total) |
|-------|--------------|-----------------------|
| 1     | 3s 218ms     | 3 (3)                 |
| 2     | 1m 54s 798ms | 1 (4)                 |
| 3     | 9m 39s 616ms | 0 (4)                 |
```
