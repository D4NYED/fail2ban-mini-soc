#!/bin/bash
OUTPUT="/var/log/centralized_security.log"
> "$OUTPUT"
# AUTH.LOG → FAILED LOGIN
zcat -f /var/log/auth.log* 2>/dev/null | grep "Failed password" | while read
line; do
DATE=$(echo "$line" | awk '{print $1" "$2" "$3}')
IP=$(echo "$line" | grep -oE 'from ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' | awk
'{print $2}')
USER=$(echo "$line" | sed -n 's/.*for \(invalid user \)\?\([^ ]*\)
from.*/\2/p')
echo "[$DATE] [SSH] [FAILED_LOGIN] [$IP] user=$USER" >> "$OUTPUT"
done
# FAIL2BAN → BAN
grep "Ban " /var/log/fail2ban.log | while read line; do
DATE=$(echo "$line" | awk '{print $1" "$2}')
IP=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo "[$DATE] [FAIL2BAN] [BAN] [$IP]" >> "$OUTPUT"
done
