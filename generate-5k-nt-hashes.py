import random, string
from passlib.hash import nthash

passwords = []

# 1. EASY (~1750)
easy_bases = ["password", "welcome", "qwerty", "admin", "summer"]

for i in range(1750):
    base = random.choice(easy_bases)
    passwords.append(f"{base}{2020 + (i % 6)}!{i}")

# 2. MEDIUM (~2000)
companies = ["Acme", "Contoso", "Globex", "Initech", "Umbrella"]

for i in range(2000):
    c = random.choice(companies)
    passwords.append(f"{c}{1000+i}@{10 + (i % 90)}")

# 3. HARD (~1250)
for i in range(1250):
    pw = ''.join(random.choice(string.ascii_letters + string.digits + "!@#$%^&*") for _ in range(10))
    passwords.append(pw + str(i))  # ensure uniqueness

# Shuffle
random.shuffle(passwords)

# Save
with open("dataset_plain.txt", "w") as f:
    f.write("\n".join(passwords))

print("Generated 5000 passwords.")

with open("dataset_plain.txt") as f, open("dataset_ntlm.txt", "w") as out:
    for line in f:
        pw = line.strip()
        if pw:
            out.write(nthash.hash(pw) + "\n")

print("Passwords converted to NT hashes.")
