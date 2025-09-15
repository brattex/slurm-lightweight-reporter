#!/usr/bin/env bash
# top_users_by_jobs.sh — Find top N users by job count from SLURM jobcomp log

# define parameters
LOG_FILE="/var/log/slurm_jobcomp.log"
TOP_N="${1:-5}"  # Default to top 5 if no argument is provided at command line

# HELPER LINES
echo "----------------------"
echo "📊 Showing top $TOP_N users by total job count from $LOG_FILE"
echo "run this script with a number (N) else default to top 5"
echo "edit the LOG_FILE value in the file else default is used"
echo "----------------------"
echo

# Validate that TOP_N is a positive integer
if ! [[ "$TOP_N" =~ ^[0-9]+$ ]] || (( TOP_N <= 0 )); then
  echo "Usage: $0 [number_of_top_users]"
  echo "Please provide a positive integer (e.g., $0 10)"
  exit 1
fi

# Extract UserId=field, strip parentheses if present, count occurrences
awk '
  {
    for (i=1; i<=NF; i++) {
      if ($i ~ /^UserId=/) {
        split($i, a, "=");
        user=a[2];
        sub(/\(.*/, "", user);  # remove trailing (UID)
        count[user]++;
      }
    }
  }
  END {
    for (u in count) {
      printf "%s %d\n", u, count[u];
    }
  }
' "$LOG_FILE" | sort -k2 -nr | head -n "$TOP_N"

