#!/usr/bin/env bash
# top_users_by_jobs.sh — Find top N users by job count from Slurm jobcomp log filtered by X days

# define parameters
LOG_FILE="/var/log/slurm_jobcomp.log"
TOP_N=5		# Default number of users
DAYS=0		# Default: all time
SAVE_FILE=""	# Default: nothing

# HELPER LINES
echo "---"
echo "* run this script with users=N [default is 5]"
echo "* set number of historical days=XX [default is ALL TIME]"
echo "* edit the LOG_FILE value in the file"
echo "---"
echo

## ARGUMENT PARSER ##
# Parse named arguments like number=10 days=30
for arg in "$@"; do
  case $arg in
    users=*)
      TOP_N="${arg#*=}"
      ;;
    days=*)
      DAYS="${arg#*=}"
      ;;
    save=*)
      SAVE_FILE="${arg#*=}"
      ;;
    *)
      echo "❌ Unknown parameter: $arg"
      echo "Usage: $0 [users=N] [days=X]"
      echo "Example: $0 users=10 days=30"
      exit 1
      ;;
  esac
done

# Validate inputs
if ! [[ "$TOP_N" =~ ^[0-9]+$ ]] || (( TOP_N <= 0 )); then
  echo "❌ Invalid number= value: must be a positive integer"
  exit 1
fi
if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || (( DAYS < 0 )); then
  echo "❌ Invalid days= value: must be zero or positive integer"
  exit 1
fi

echo "📊 Showing top $TOP_N users by job count from $LOG_FILE"
echo "   ====================================================="
[[ "$DAYS" -gt 0 ]] && echo "🕒 Filtering jobs from the last $DAYS days"

# Calculate cutoff timestamp if DAYS is set
if (( DAYS > 0 )); then
  cutoff=$(date -d "-$DAYS days" +%s)
fi

RESULT=$(awk -v cutoff="$cutoff" -v days="$DAYS" '
  {
    start = ""; user = "";
    for (i=1; i<=NF; i++) {
      if ($i ~ /^StartTime=/) {
        split($i, a, "=");
        gsub("T", " ", a[2]);
        start=a[2];
      }
      if ($i ~ /^UserId=/) {
        split($i, b, "=");
        user=b[2];
        sub(/\(.*/, "", user);
      }
    }

    if (user != "") {
      if (days == 0 || (start != "" && mktime(gensub(/[-:]/, " ", "g", start)) >= cutoff)) {
        count[user]++;
      }
    }
  }
  END {
    for (u in count) {
      printf "%s %d\n", u, count[u];
    }
  }
' "$LOG_FILE" | sort -k2 -nr | head -n "$TOP_N")

# Output to file or stdout
if [[ -n "$SAVE_FILE" ]]; then
  echo "$RESULT" > "$SAVE_FILE"
  echo "💾 Results saved to $SAVE_FILE"
else
  echo "$RESULT"
fi
