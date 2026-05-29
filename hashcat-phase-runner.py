#!/usr/bin/env python3

"""
phase_runner.py

A lightweight wrapper around hashcat to execute password cracking in structured phases.

This tool is designed to:
- Run hashcat in defined phases
- Keep output readable (minimal mode)
- Preserve interactive control (s/p/q/etc.)
- Allow reproducible configurations via JSON

It does NOT optimise cracking — it structures it.

----------------------------------------
Example usage:

python phase_runner.py --config config.json
python phase_runner.py --config config.json --show full

----------------------------------------
Default paths:
- Hash dataset -> .\
- Wordlists    -> .\wordlists\
- Rules        -> .\rules\
----------------------------------------
"""

import subprocess
import argparse
import os
import json
import sys
import time

WORDLIST_DIR = ".\\wordlists"
RULES_DIR = ".\\rules"


# ---------- Path helpers ----------

def resolve_path(path, base_dir=None):
    if os.path.exists(path):
        return path

    if base_dir:
        candidate = os.path.join(base_dir, path)
        return candidate

    return path


def validate_file(path, description):
    if not os.path.exists(path):
        print(f"[!] ERROR: {description} not found -> {path}")
        sys.exit(1)


# ---------- Config ----------

def load_config(config_file):
    try:
        with open(config_file, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"[!] ERROR: Failed to load config file: {e}")
        sys.exit(1)


# ---------- Phase execution ----------

def run_phase(hashfile, hashmode, wordlist, rule, flags, session, phase_id, show_mode):

    # Subtle colors (not loud)
    YELLOW = "\033[33m"
    DIM = "\033[2m"
    GREEN = "\033[92m"
    RESET = "\033[0m"
    BOLD = "\033[1m"

    cmd = [
        "hashcat",
        "-m", hashmode,
        hashfile,
        wordlist,
        "--session", session
    ]

    if rule:
        cmd += ["-r", rule]

    if flags:
        cmd += flags

    # -------- Cleaner phase header --------
    print(f"\n{DIM}{'-'*40}{RESET}")
    print(f"{BOLD}[+] Phase {phase_id}{RESET}")
    print(f"wordlist: {os.path.basename(wordlist)}")
    if rule:
        print(f"ruleset : {os.path.basename(rule)}")
    print(f"{DIM}{'-'*40}{RESET}\n")

    start_time = time.time()

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=sys.stdin,
        text=True,
        bufsize=1
    )

    show_full_block = False

    for line in process.stdout:

        if show_mode == "full":
            print(line, end="")
            continue

        stripped = line.strip()

        # ---- detect full status after pressing "s" ----
        if "Speed.#01" in line:
            show_full_block = True

        if show_full_block:
            print(stripped)  # NO coloring here
            continue

        # ---- Minimal mode ----

        if "Keyspace" in line:
            print(f"{GREEN}{stripped}{RESET}")

        elif "Speed.#*" in line:
            print(f"{GREEN}{stripped}{RESET}")

        elif "Recovered" in line:
            print(f"{GREEN}{stripped}{RESET}")

        elif "[s]tatus" in line:
            show_full_block = False
            print(stripped)  # keep white

    process.wait()

    duration = time.time() - start_time

    print(f"\n{DIM}{'-'*40}{RESET}")
    print(f"{BOLD}[+] Phase {phase_id} completed{RESET} ({duration:.2f}s)")
    print(f"{DIM}{'-'*40}{RESET}\n")

    # -------- Correct summary --------
    try:
        print(f"{DIM}[*] Cracked so far:{RESET}")
        subprocess.run([
            "hashcat",
            "-m", hashmode,
            "--show",
            hashfile
        ])
    except Exception:
        pass


# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(description="Phased hashcat runner")

    parser.add_argument(
        "--config",
        required=True,
        help="Path to JSON config file"
    )

    parser.add_argument(
        "--show",
        choices=["minimal", "full"],
        default="minimal",
        help="Output mode (default: minimal)"
    )

    args = parser.parse_args()

    config = load_config(args.config)

    params = config.get("parameters", {})
    phases = config.get("phases", [])

    session = params.get("sessionName", "phased-run")
    hashmode = params.get("hashMode", "1000")
    flags = params.get("flags", [])

    hashfile = resolve_path(params.get("hashDataset"))

    validate_file(hashfile, "Hash dataset")

    print("\n" + "="*40)
    print("[+] Starting phased hashcat run")
    print(f"Session : {session}")
    print(f"Hashes  : {hashfile}")
    print(f"Mode    : {hashmode}")
    print(f"Flags   : {flags}")
    print("="*40)

    for i, phase in enumerate(phases, start=1):

        wordlist = resolve_path(phase.get("wordlist"), WORDLIST_DIR)
        rule = phase.get("rule")

        if rule:
            rule = resolve_path(rule, RULES_DIR)

        validate_file(wordlist, f"Wordlist (phase {i})")

        if rule:
            validate_file(rule, f"Rule (phase {i})")

        run_phase(
            hashfile=hashfile,
            hashmode=hashmode,
            wordlist=wordlist,
            rule=rule,
            flags=flags,
            session=session,
            phase_id=i,
            show_mode=args.show
        )

    print("\n[+] All phases completed.\n")


if __name__ == "__main__":
    main()