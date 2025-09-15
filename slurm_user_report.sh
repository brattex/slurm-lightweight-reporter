#!/usr/bin/env bash
# slurm_report.sh — Summarize SLURM jobs for a user from jobcomp logs

LOG_FILE="/var/log/slurm_jobcomp.log"
USER_ID=""
DAYS=0

# Usage Help Tips
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: $0 user=USER_ID [days=X]"
  echo "You must specify a USER_ID to run this report"
  exit 0
fi

# Parse named arguments
for arg in "$@"; do
  case $arg in
    user=*)
      USER_ID="${arg#*=}"
      ;;
    days=*)
      DAYS="${arg#*=}"
      ;;
    *)
      echo "❌ Unknown parameter: $arg"
      echo "Usage: $0 user=USER_ID [days=X]"
      exit 1
      ;;
  esac
done

if [[ -z "$USER_ID" ]]; then
  echo "❌ No user specified. Aborting."
  exit 1
fi

echo "📊 Running report for user: $USER_ID"
[[ "$DAYS" -gt 0 ]] && echo "🕒 Filtering jobs from the last $DAYS days"

# Calculate cutoff timestamp
if (( DAYS > 0 )); then
  cutoff=$(date -d "-$DAYS days" +%s)
fi

# Initialize counters
declare -A symbol_count=( ["✅"]=0 ["❌"]=0 ["🚫"]=0 ["⚠"]=0 )
total_duration=0
job_count=0

# Helper: convert seconds to HH:MM:SS
hms() {
  local s=$1
  printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60))
}

# Process matching lines
while IFS= read -r line; do
  [[ "$line" == *"UserId=${USER_ID}"* ]] || continue

  # Extract fields
  jobid=$(echo "$line" | grep -oP 'JobId=\K[^ ,]+')
  state=$(echo "$line" | grep -oP 'JobState=\K[^ ,]+')
  start=$(echo "$line" | grep -oP 'StartTime=\K[^ ,]+')
  end=$(echo "$line" | grep -oP 'EndTime=\K[^ ,]+')

  # Normalize timestamps
  if [[ -n "$start" && -n "$end" ]]; then
    start_epoch=$(date -d "${start/T/ }" +%s 2>/dev/null)
    end_epoch=$(date -d "${end/T/ }" +%s 2>/dev/null)

    # Skip if outside time window
    if (( DAYS > 0 && start_epoch < cutoff )); then
      continue
    fi

    if (( end_epoch >= start_epoch )); then
      duration=$((end_epoch - start_epoch))
      total_duration=$((total_duration + duration))
      ((job_count++))
    fi
  fi

  # Tally job state
  case "$state" in
    COMPLETED) ((symbol_count["✅"]++)) ;;
    FAILED)    ((symbol_count["❌"]++)) ;;
    CANCELLED|CANCELLED*) ((symbol_count["🚫"]++)) ;;
    TIMEOUT|NODE_FAIL|PREEMPTED|OUT_OF_MEMORY|BOOT_FAIL) ((symbol_count["⚠"]++)) ;;
  esac

done < "$LOG_FILE"

# Output summary
echo ""
echo "🔢 Job Status Summary for '$USER_ID':"
printf "✅ %d\n" "${symbol_count["✅"]}"
printf "❌ %d\n" "${symbol_count["❌"]}"
printf "🚫 %d\n" "${symbol_count["🚫"]}"
printf "⚠ %d\n" "${symbol_count["⚠"]}"

echo ""
echo "⏱ Duration Summary:"
echo "Total jobs with duration: $job_count"
echo "Total runtime: $total_duration seconds ($(hms "$total_duration"))"

if (( job_count > 0 )); then
  avg=$((total_duration / job_count))
  echo "Average runtime: $avg seconds ($(hms "$avg"))"
else
  echo "Average runtime: N/A"
fi
