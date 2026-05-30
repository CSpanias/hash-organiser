#!/usr/bin/env python3

####################################################################################################
# Hashcat Phase Cracker v1.0                                                                        #
# Author: Charalampos Spanias (mollysec) & M365 Copilot                                             #
# Date: 30 May 2026                                                                                #
#                                                                                                  #
# Description:                                                                                     #
#   Minimal phased hashcat runner for password auditing workflows.                                 #
#                                                                                                  #
#   Part 3 companion tool:                                                                          #
#   https://mollysec.com/posts/password-audits-part-3/                                              #
#                                                                                                  #
#   Focus: Simplicity and clarity.                                                                 #
#                                                                                                  #
#   Estimation Model:                                                                              #
#     Effective speed = Raw benchmark speed / 5                                                     #
#                                                                                                  #
####################################################################################################

import subprocess
import argparse
import os
import json
import sys
import time
import re

WORDLIST_DIR = ".\\wordlists"
RULES_DIR = ".\\rules"
CACHE_FILE = ".linecache.json"


# ---------- Cache ----------

def load_cache():
    if os.path.exists(CACHE_FILE):
        return json.load(open(CACHE_FILE))
    return {}

def save_cache(cache):
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=2)

def get_line_count(file, cache):
    key = os.path.basename(file)

    if key in cache:
        return cache[key]

    print(f"[*] Counting {key} (first time only)...")

    count = 0
    with open(file, "rb") as f:
        while chunk := f.read(1024 * 1024):
            count += chunk.count(b'\n')

    cache[key] = count
    return count


# ---------- Helpers ----------

def resolve_path(path, base):
    return path if os.path.exists(path) else os.path.join(base, path)

def validate_file(path):
    if not os.path.exists(path):
        print(f"[!] Missing file: {path}")
        sys.exit(1)

def human_time(seconds):
    ms = int((seconds - int(seconds)) * 1000)
    seconds = int(seconds)

    mins, secs = divmod(seconds, 60)
    hours, mins = divmod(mins, 60)

    parts = []
    if hours:
        parts.append(f"{hours}h")
    if mins:
        parts.append(f"{mins}m")
    if secs:
        parts.append(f"{secs}s")
    if ms:
        parts.append(f"{ms}ms")

    return " ".join(parts) if parts else "0s"

def parse_recovered(line):
    m = re.search(r"Recovered.*?: (\d+)/(\d+)", line)
    return int(m.group(1)) if m else 0


# ---------- Benchmark ----------

def run_benchmark(mode, flags):
    cmd = ["hashcat", "-b", "-m", mode] + flags

    print("[*] Running benchmark...")

    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    m = re.search(r"Speed.#\*.*?:\s*([\d.]+)\s*([KMG]?H/s)", result.stdout)

    if not m:
        print("[!] Failed to parse benchmark")
        sys.exit(1)

    val = float(m.group(1))
    unit = m.group(2)

    mult = {"H/s":1, "KH/s":1e3, "MH/s":1e6, "GH/s":1e9}
    speed = val * mult[unit]

    print(f"[*] Raw benchmark speed: {val} {unit}")
    print("[*] Using effective speed: benchmark / 5")

    return speed / 5


# ---------- Estimation ----------

def estimate_phase(wl, rule, speed, cache):

    wl_count = get_line_count(wl, cache)

    if not rule:
        keyspace = wl_count
    else:
        rule_count = get_line_count(rule, cache)
        keyspace = wl_count * rule_count

    est_time = keyspace / speed

    return keyspace, est_time


# ---------- Estimate Mode ----------

def estimate_only(phases, params):

    cache = load_cache()
    speed = run_benchmark(params["hashMode"], params.get("flags", []))

    rows = []
    total_time = 0

    for i, ph in enumerate(phases, 1):

        wl = resolve_path(ph["wordlist"], WORDLIST_DIR)
        rule = resolve_path(ph["rule"], RULES_DIR) if "rule" in ph else None

        keyspace, est_time = estimate_phase(wl, rule, speed, cache)

        total_time += est_time

        rows.append([
            str(i),
            os.path.basename(wl),
            os.path.basename(rule) if rule else "None",
            f"{keyspace:,}",
            human_time(est_time)
        ])

    save_cache(cache)

    headers = ["Phase", "Wordlist", "Ruleset", "Keyspace", "Est. Time"]
    widths = [max(len(str(x)) for x in col) for col in zip(headers, *rows)]

    print("\n# Phase Estimation\n")

    print("| " + " | ".join(headers[i].ljust(widths[i]) for i in range(len(headers))) + " |")
    print("|-" + "-|-".join("-"*w for w in widths) + "-|")

    for r in rows:
        print("| " + " | ".join(r[i].ljust(widths[i]) for i in range(len(r))) + " |")

    print(f"\n[*] Total Estimated Time: {human_time(total_time)}")
    print("[!] Estimates are approximate (based on benchmark/5 model)\n")


# ---------- Phase Execution ----------

def run_phase(hashfile, mode, wl, rule, flags, session, pid, prev_total):

    cmd = ["hashcat", "-m", mode, hashfile, wl, "--session", session]

    if rule:
        cmd += ["-r", rule]
    if flags:
        cmd += flags

    print("\n" + "-"*40)
    print(f"[+] Phase {pid}")
    print(f"Wordlist : {os.path.basename(wl)}")
    print(f"Ruleset  : {os.path.basename(rule) if rule else 'None'}")
    print("-"*40)

    print(f"[+] Phase {pid} running...")

    start = time.time()

    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    duration = time.time() - start

    started = "N/A"
    total = 0

    for line in result.stdout.splitlines():
        if line.startswith("Started"):
            started = line.split(":",1)[1].strip()
        elif line.startswith("Recovered........"):
            total = parse_recovered(line)

    new = total - prev_total

    print(f"\n[+] Phase {pid} completed")
    print(f"Started        : {started}")
    print(f"Duration       : {human_time(duration)}")
    print(f"Recovered      : {new}")
    print(f"Total Recovered: {total}")

    return total, duration


# ---------- Report ----------

def report(results):

    print("\n# Phase Report\n")

    headers = ["Phase", "Duration", "Recovered (New/Total)"]

    rows = []
    prev = 0

    for i, r in enumerate(results, 1):
        new = r["recovered"] - prev
        prev = r["recovered"]

        rows.append([
            str(i),
            human_time(r["duration"]),
            f"{new} ({r['recovered']})"
        ])

    widths = [max(len(str(x)) for x in col) for col in zip(headers, *rows)]

    print("| " + " | ".join(headers[i].ljust(widths[i]) for i in range(len(headers))) + " |")
    print("|-" + "-|-".join("-"*w for w in widths) + "-|")

    for row in rows:
        print("| " + " | ".join(row[i].ljust(widths[i]) for i in range(len(row))) + " |")

    print()


# ---------- Main ----------

def main():

    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    p.add_argument("--estimate", action="store_true")
    p.add_argument("--report", action="store_true")

    args = p.parse_args()

    cfg = json.load(open(args.config))
    params = cfg["parameters"]
    phases = cfg["phases"]

    if args.estimate:
        estimate_only(phases, params)
        return

    hashfile = resolve_path(params["hashDataset"], ".")
    validate_file(hashfile)

    print("\n" + "="*40)
    print("[+] Starting phased hashcat run")
    print(f"Session : {params['sessionName']}")
    print(f"Hashes  : {hashfile}")
    print(f"Mode    : {params['hashMode']}")
    print("="*40)

    results = []
    prev_total = 0

    for i, ph in enumerate(phases, 1):

        wl = resolve_path(ph["wordlist"], WORDLIST_DIR)
        validate_file(wl)

        rule = resolve_path(ph["rule"], RULES_DIR) if "rule" in ph else None

        total, duration = run_phase(
            hashfile,
            params["hashMode"],
            wl,
            rule,
            params.get("flags", []),
            params["sessionName"],
            i,
            prev_total
        )

        results.append({"recovered": total, "duration": duration})
        prev_total = total

    print("\n[+] All phases completed\n")

    if args.report:
        report(results)


if __name__ == "__main__":
    main()
