#!/usr/bin/env bash
# slurm_report.sh — Summarize SLURM jobs for a user from jobcomp logs

LOG_FILE="/var/log/slurm_jobcomp.log"
USER_MODE="$1"
DAYS=0

# Usage Help Tips
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: $0 USER_ID [days=X]"
  echo "       $0 file=filename.txt [days=X]"
  echo "You must specify a USER_ID or a file containing user IDs to run this report"
  echo "Example: $0 jdoe days=30"
  echo "         $0 file=top5users.txt days=7"
  exit 0
fi

# Parse optional days=X argument
if [[ "$2" =~ ^days=([0-9]+)$ ]]; then
  DAYS="${BASH_REMATCH[1]}"
fi

# Validate user
if [[ -z "$USER_MODE" ]]; then
  echo "❌ No USER_ID specified. Aborting."
  exit 1
fi

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

# Function to run report for a single user
run_report_for_user() {
  local USER_ID="$1"
  declare -A symbol_count=( ["✅"]=0 ["❌"]=0 ["🚫"]=0 ["⚠"]=0 )
  local total_duration=0
  local job_count=0

  echo ""
  echo "📊 Running report for user: $USER_ID"
  [[ "$DAYS" -gt 0 ]] && echo "🕒 Filtering jobs from the last $DAYS days"

  while IFS= read -r line; do
    [[ "$line" == *"UserId=${USER_ID}"* ]] || continue

    jobid=$(echo "$line" | grep -oP 'JobId=\K[^ ,]+')
    state=$(echo "$line" | grep -oP 'JobState=\K[^ ,]+')
    start=$(echo "$line" | grep -oP 'StartTime=\K[^ ,]+')
    end=$(echo "$line" | grep -oP 'EndTime=\K[^ ,]+')

    if [[ -n "$start" && -n "$end" ]]; then
      start_epoch=$(date -d "${start/T/ }" +%s 2>/dev/null)
      end_epoch=$(date -d "${end/T/ }" +%s 2>/dev/null)

      if (( DAYS > 0 && start_epoch < cutoff )); then
        continue
      fi

      if (( end_epoch >= start_epoch )); then
        duration=$((end_epoch - start_epoch))
        total_duration=$((total_duration + duration))
        ((job_count++))
      fi
    fi

    case "$state" in
      COMPLETED) ((symbol_count["✅"]++)) ;;
      FAILED)    ((symbol_count["❌"]++)) ;;
      CANCELLED|CANCELLED*) ((symbol_count["🚫"]++)) ;;
      TIMEOUT|NODE_FAIL|PREEMPTED|OUT_OF_MEMORY|BOOT_FAIL) ((symbol_count["⚠"]++)) ;;
    esac

  done < "$LOG_FILE"

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
}

# Main logic: single user or file mode
if [[ "$USER_MODE" =~ ^file=(.+)$ ]]; then
  USER_FILE="${BASH_REMATCH[1]}"
  if [[ ! -f "$USER_FILE" ]]; then
    echo "❌ File not found: $USER_FILE"
    exit 1
  fi
  while IFS= read -r line; do
    user=$(echo "$line" | awk '{print $1}')
    [[ -n "$user" ]] && run_report_for_user "$user"
  done < "$USER_FILE"
else
  if [[ -z "$USER_MODE" ]]; then
    echo "❌ No USER_ID specified. Aborting."
    exit 1
  fi
  run_report_for_user "$USER_MODE"
fi
